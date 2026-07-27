import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../controllers/user_controller.dart';
import '../models/action_item.dart';
import '../models/ai_chat.dart';
import '../models/baby.dart';
import '../models/baby_cloud_source.dart';
import '../models/cftts_config.dart';
import '../models/growth_record.dart';
import '../models/log.dart';
import '../models/milestone_record.dart';
import '../models/openai_config.dart';
import '../models/openai_tts_config.dart';
import '../models/poop_record.dart';
import '../models/product.dart';
import '../models/story_session.dart';
import '../models/user_profile.dart';
import '../services/baby_cloud_service.dart';
import '../services/encyclopedia_service.dart';
import '../services/quiz_service.dart';
import '../services/storage_service.dart';
import '../services/story_management_service.dart';
import '../services/webdav_backup_v2_service.dart';
import '../utils/sync_ids.dart';

/// 家庭同步服务：通过自部署的 Cloudflare Worker + D1 在多台设备间同步核心数据。
///
/// 设计：
/// - 计数器（星星/存钱罐/零花钱）走「操作累加」：本地余额变化被影子快照捕获为
///   delta 操作，服务端按 op_id 幂等累加，两个大人并发加星不丢失；
/// - 记录级数据（宝宝/日志/行为/商品/成长/里程碑/便便/AI聊天/故事会话）
///   按内容哈希与本地清单(manifest)做差异推送，updatedAt 新者胜，删除用墓碑；
/// - 配置与 AI 内容的其余部分按「整段快照」同步（单条记录，新者胜）；
/// - 不配置服务端点即纯本地模式，无任何网络行为。
class FamilySyncService extends GetxService with WidgetsBindingObserver {
  static const _stateBoxName = 'family_sync_state';
  static const Duration _pushDebounce = Duration(seconds: 4);
  static const Duration _periodicInterval = Duration(minutes: 3);
  // 自动同步的最小间隔：多个触发源（回前台/定时/改动）在窗口内合并为一次
  static const Duration _minAutoInterval = Duration(seconds: 20);
  static const Duration _httpTimeout = Duration(seconds: 20);
  // 免费版 Worker 单请求 CPU 限额较低，批量取小值避免 1102 错误
  static const int _pushBatchSize = 60;
  // 除 v2 备份白名单外，家庭同步额外纳入的 settingsBox 键
  static const List<String> _extraSettingsKeys = [
    'baby_cloud_auto_cache_cleanup_days',
  ];
  // 每 N 次自动同步做一次全量校验（兜底未被监听捕获的变更）；手动同步总是全量
  static const int _fullVerifyEvery = 5;
  // 单条记录/快照的 payload 上限（字符数），防止大对象打爆 Worker CPU 限额
  static const int _maxRecordPayloadChars = 300000;
  static const int _maxSnapshotPayloadChars = 600000;

  final StorageService _storage = Get.find<StorageService>();

  late Box _state;

  final RxBool enabled = false.obs;
  final RxString endpoint = ''.obs;
  final RxString username = ''.obs;
  final RxString role = ''.obs;
  final RxString familyName = ''.obs;
  final RxBool syncing = false.obs;
  final Rx<DateTime?> lastSyncAt = Rx<DateTime?>(null);
  final RxString lastError = ''.obs;

  Timer? _debounceTimer;
  Timer? _periodicTimer;
  bool _applyingRemote = false;
  bool _syncRunning = false;
  bool _syncQueued = false;
  DateTime? _lastSyncEndedAt;
  int _autoSyncCounter = 0;
  final Set<String> _dirtySections = <String>{};
  final List<StreamSubscription> _watchSubs = [];
  final List<Worker> _everWorkers = [];

  bool get isLoggedIn => (_state.get('token') as String? ?? '').isNotEmpty;
  bool get isOwner => role.value == 'owner';
  String get _token => _state.get('token') as String? ?? '';

  Future<FamilySyncService> init() async {
    _state = await Hive.openBox(_stateBoxName);
    enabled.value = _state.get('enabled') as bool? ?? false;
    endpoint.value = _state.get('endpoint') as String? ?? '';
    username.value = _state.get('username') as String? ?? '';
    role.value = _state.get('role') as String? ?? '';
    familyName.value = _state.get('familyName') as String? ?? '';
    final lastAt = _state.get('lastSyncAt') as String?;
    if (lastAt != null) lastSyncAt.value = DateTime.tryParse(lastAt);
    final dirtyRaw = _state.get('dirty') as String? ?? '[]';
    try {
      _dirtySections
          .addAll((jsonDecode(dirtyRaw) as List).map((e) => e.toString()));
    } catch (_) {}

    WidgetsBinding.instance.addObserver(this);
    if (enabled.value && isLoggedIn) {
      // 一次性自愈：旧版分页游标可能跳过了同 seq 批次的部分记录，
      // 归零游标全量重拉一遍（应用是幂等的，不会产生重复数据）。
      if (_state.get('pullCursorFixV2') != true) {
        await _state.put('lastSeq', 0);
        await _state.put('pullCursorFixV2', true);
      }
      _startWatchers();
      _startPeriodic();
      // 启动后延迟触发一次同步，避免拖慢冷启动
      Future.delayed(const Duration(seconds: 6), () => syncNow());
    } else {
      await _state.put('pullCursorFixV2', true);
    }
    return this;
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopWatchers();
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && enabled.value && isLoggedIn) {
      syncNow();
    }
  }

  // ---------------------------------------------------------------------
  // 配置与认证
  // ---------------------------------------------------------------------

  Future<void> saveEndpoint(String value) async {
    var trimmed = value.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    endpoint.value = trimmed;
    await _state.put('endpoint', trimmed);
  }

  /// 连通性测试：确认端点确实是 StarBank 同步服务端。
  Future<void> testEndpoint() async {
    final data = await _api('GET', '/', withAuth: false);
    if (data['service'] != 'starbank-family-sync') {
      throw FamilySyncException('该地址不是 StarBank 同步服务端，请检查端点配置');
    }
  }

  Future<Map<String, dynamic>> _api(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool withAuth = true,
    Map<String, String>? query,
  }) async {
    final base = endpoint.value;
    if (base.isEmpty) {
      throw FamilySyncException('请先配置服务端地址');
    }
    var uri = Uri.parse('$base$path');
    if (query != null) uri = uri.replace(queryParameters: query);
    final headers = <String, String>{'content-type': 'application/json'};
    if (withAuth) {
      if (_token.isEmpty) throw FamilySyncException('未登录');
      headers['authorization'] = 'Bearer $_token';
    }

    // 所有接口均幂等（记录 LWW、计数按 opId 去重），5xx/网络错误自动重试。
    const maxAttempts = 3;
    http.Response res;
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        if (method == 'GET') {
          res = await http.get(uri, headers: headers).timeout(_httpTimeout);
        } else {
          res = await http
              .post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(_httpTimeout);
        }
      } on TimeoutException {
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
        throw FamilySyncException('连接服务端超时');
      } on SocketException catch (e) {
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
        throw FamilySyncException('无法连接服务端: ${e.message}');
      }
      if (res.statusCode >= 500 && attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: attempt * 2));
        continue;
      }
      break;
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      final bodyText = utf8
          .decode(res.bodyBytes, allowMalformed: true)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final cfCode = RegExp(r'error code:\s*(\d+)', caseSensitive: false)
          .firstMatch(bodyText)
          ?.group(1);
      if (res.statusCode == 503 ||
          res.statusCode == 502 ||
          res.statusCode == 521 ||
          res.statusCode == 522) {
        throw FamilySyncException('服务端暂时不可用 (HTTP ${res.statusCode}'
            '${cfCode != null ? '，Cloudflare 错误码 $cfCode' : ''})：'
            '${cfCode == '1102' ? '单次请求超出免费版 CPU 限额，已自动减小批量，请再试一次；' : ''}'
            '请检查 Worker 是否已部署、自定义域名是否生效、防火墙/Bot 拦截是否放行');
      }
      throw FamilySyncException('服务端返回异常 (HTTP ${res.statusCode})'
          '${bodyText.isEmpty ? '' : '：${bodyText.substring(0, bodyText.length > 120 ? 120 : bodyText.length)}'}');
    }
    if (res.statusCode == 401 && withAuth) {
      // 令牌失效：清除登录态，要求重新登录
      await _clearAuth();
      throw FamilySyncException(data['error']?.toString() ?? '登录已失效');
    }
    if (res.statusCode >= 400) {
      throw FamilySyncException(
          data['error']?.toString() ?? 'HTTP ${res.statusCode}');
    }
    return data;
  }

  Future<void> _saveAuth(Map<String, dynamic> data) async {
    await _state.putAll({
      'token': data['token'],
      'userId': data['user']?['id'],
      'username': data['user']?['username'],
      'role': data['user']?['role'],
      'familyId': data['family']?['id'],
      'familyName': data['family']?['name'],
    });
    username.value = data['user']?['username']?.toString() ?? '';
    role.value = data['user']?['role']?.toString() ?? '';
    familyName.value = data['family']?['name']?.toString() ?? '';
  }

  Future<void> _clearAuth() async {
    await _state.deleteAll(
        ['token', 'userId', 'username', 'role', 'familyId', 'familyName']);
    username.value = '';
    role.value = '';
    familyName.value = '';
  }

  /// 注册（首次注册自动创建家庭并成为主号），随后全量上传本地数据。
  Future<void> register({
    required String user,
    required String password,
    String? familyDisplayName,
  }) async {
    final data = await _api('POST', '/api/register', withAuth: false, body: {
      'username': user,
      'password': password,
      if (familyDisplayName?.trim().isNotEmpty == true)
        'familyName': familyDisplayName!.trim(),
    });
    await _saveAuth(data);
    await _resetSyncCursor();
    await _enableInternal();
    // 首次全量上传在后台进行，账号页展示同步进度，不阻塞注册流程
    unawaited(syncNow());
  }

  /// 登录。返回是否需要用户做「首次合并」二选一。
  Future<FirstLoginResult> login({
    required String user,
    required String password,
  }) async {
    final data = await _api('POST', '/api/login', withAuth: false, body: {
      'username': user,
      'password': password,
    });
    await _saveAuth(data);

    final stats = await _api('GET', '/api/sync/stats');
    final cloudHasData = (stats['recordCount'] as num? ?? 0) > 0 ||
        (stats['counterOpCount'] as num? ?? 0) > 0;
    final localHasData = _storage.babyBox.isNotEmpty ||
        _storage.logBox.isNotEmpty ||
        _storage.productBox.isNotEmpty;

    if (cloudHasData && localHasData) {
      // 等待用户在 UI 上二选一（adoptCloud / mergeUpload）
      return FirstLoginResult.needMergeChoice;
    }
    await _resetSyncCursor();
    await _enableInternal();
    unawaited(syncNow());
    return FirstLoginResult.done;
  }

  /// 首次合并选择：以云端为准（本地核心数据先做安全快照再被替换）。
  Future<String> adoptCloud() async {
    final backupPath = await _writeLocalSafetySnapshot();
    _applyingRemote = true;
    try {
      await _storage.babyBox.clear();
      await _storage.logBox.clear();
      await _storage.actionBox.clear();
      await _storage.productBox.clear();
      await _storage.growthRecordBox.clear();
      await _storage.milestoneRecordBox.clear();
      try {
        final poopBox = await Hive.openBox<PoopRecord>('poop_records');
        await poopBox.clear();
      } catch (_) {}
      try {
        final chatBox = await Hive.openBox<dynamic>('ai_chats');
        await chatBox.clear();
      } catch (_) {}
      try {
        final sessionBox = await Hive.openBox<dynamic>('story_sessions');
        await sessionBox.clear();
      } catch (_) {}
    } finally {
      _applyingRemote = false;
    }
    await _resetSyncCursor();
    await _enableInternal();
    unawaited(syncNow());
    return backupPath;
  }

  /// 首次合并选择：合并上传（本地与云端数据都保留，可能出现重复宝宝需手动清理）。
  Future<void> mergeUpload() async {
    await _resetSyncCursor();
    await _enableInternal();
    unawaited(syncNow());
  }

  Future<void> _resetSyncCursor() async {
    await _state.putAll({
      'lastSeq': 0,
      'manifest': '{}',
      'shadow': '{}',
      'ops': '[]',
      // 基线对账标记：下一次同步先拉取服务端计数总额，按
      // 「delta = 本地 − 服务端」修正，而不是把全量本地余额当增量推上去
      // （否则重复登录会导致余额翻倍）。
      'baselinePending': true,
    });
    _markAllDirty();
  }

  // -------------------- 脏段跟踪 --------------------

  List<String> get _allSectionNames => [
        for (final s in _recordSections) s.name,
        for (final s in _snapshotSections) s.name,
      ];

  void _markDirty(String section) {
    if (_dirtySections.add(section)) {
      _persistDirty();
    }
    _scheduleSync();
  }

  void _markAllDirty() {
    _dirtySections.addAll(_allSectionNames);
    _persistDirty();
  }

  void _persistDirty() {
    _state.put('dirty', jsonEncode(_dirtySections.toList()));
  }

  Future<void> _enableInternal() async {
    enabled.value = true;
    await _state.put('enabled', true);
    _startWatchers();
    _startPeriodic();
  }

  /// 退出登录并停用同步（本地数据保留）。
  Future<void> logoutAndDisable() async {
    try {
      if (isLoggedIn) await _api('POST', '/api/logout');
    } catch (_) {}
    await _clearAuth();
    enabled.value = false;
    await _state.put('enabled', false);
    _stopWatchers();
    _periodicTimer?.cancel();
  }

  Future<void> changePassword(String oldPassword, String newPassword) {
    return _api('POST', '/api/password', body: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }

  // 成员管理（主号）
  Future<List<Map<String, dynamic>>> fetchMembers() async {
    final data = await _api('GET', '/api/members');
    return (data['members'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> createMember(String user, String password) {
    return _api('POST', '/api/members',
        body: {'username': user, 'password': password});
  }

  Future<void> resetMemberPassword(String userId, String password) {
    return _api('POST', '/api/members/reset',
        body: {'userId': userId, 'password': password});
  }

  Future<void> removeMember(String userId) {
    return _api('POST', '/api/members/remove', body: {'userId': userId});
  }

  // ---------------------------------------------------------------------
  // 变更监听
  // ---------------------------------------------------------------------

  void _startWatchers() {
    _stopWatchers();
    void watch(Box box, String section) {
      _watchSubs.add(box.watch().listen((_) {
        if (_applyingRemote) return;
        _markDirty(section);
      }));
    }

    watch(_storage.babyBox, 'babies');
    watch(_storage.logBox, 'logs');
    watch(_storage.actionBox, 'actions');
    watch(_storage.productBox, 'products');
    watch(_storage.growthRecordBox, 'growth_records');
    watch(_storage.milestoneRecordBox, 'milestone_records');
    watch(_storage.babyCloudSourceBox, 'baby_cloud_sources');
    watch(_storage.userBox, 'user_profile');
    // settingsBox 里有大量高频写入的本地状态键（浏览位置等），
    // 只有同步白名单内的键变化才值得触发一次同步。
    _watchSubs.add(_storage.settingsBox.watch().listen((event) {
      if (_applyingRemote) return;
      final key = event.key?.toString() ?? '';
      if (WebDavBackupV2Service.shouldBackupGenericSetting(key)) {
        _markDirty('settings');
      }
    }));
    // 便便记录：其他页面均以 Box<PoopRecord> 打开，这里保持同类型
    unawaited(() async {
      try {
        final box = Hive.isBoxOpen('poop_records')
            ? Hive.box<PoopRecord>('poop_records')
            : await Hive.openBox<PoopRecord>('poop_records');
        if (_watchSubs.isEmpty) return; // 已 stop
        watch(box, 'poop_records');
      } catch (_) {}
    }());
    // 测验题库 / 百科题库通过服务内存列表感知变化
    if (Get.isRegistered<QuizService>()) {
      _everWorkers.add(ever(Get.find<QuizService>().questions, (_) {
        if (!_applyingRemote) _markDirty('quiz');
      }));
    }
    if (Get.isRegistered<EncyclopediaService>()) {
      _everWorkers.add(ever(Get.find<EncyclopediaService>().questions, (_) {
        if (!_applyingRemote) _markDirty('encyclopedia');
      }));
    }
    // 其余数据段（AI 聊天/故事/各类配置盒）由周期性全量校验兜底
  }

  void _stopWatchers() {
    for (final sub in _watchSubs) {
      sub.cancel();
    }
    _watchSubs.clear();
    for (final worker in _everWorkers) {
      worker.dispose();
    }
    _everWorkers.clear();
  }

  void _startPeriodic() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_periodicInterval, (_) {
      if (enabled.value && isLoggedIn) syncNow();
    });
  }

  void _scheduleSync() {
    if (!enabled.value || !isLoggedIn) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_pushDebounce, () => syncNow());
  }

  // ---------------------------------------------------------------------
  // 同步主流程
  // ---------------------------------------------------------------------

  Future<void> syncNow({bool manual = false}) async {
    if (!enabled.value || !isLoggedIn) return;
    if (_syncRunning) {
      _syncQueued = true;
      return;
    }
    // 自动触发的同步做节流：距上次完成太近时合并到窗口结束后执行一次
    if (!manual && _lastSyncEndedAt != null) {
      final elapsed = DateTime.now().difference(_lastSyncEndedAt!);
      if (elapsed < _minAutoInterval) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(_minAutoInterval - elapsed, () => syncNow());
        return;
      }
    }
    _syncRunning = true;
    syncing.value = true;
    lastError.value = '';
    try {
      final baseline = _state.get('baselinePending') == true;
      // 手动同步、基线对账与每 N 次自动同步做全量校验；平时只处理脏数据段。
      var full = manual || baseline;
      if (!full) {
        _autoSyncCounter++;
        if (_autoSyncCounter >= _fullVerifyEvery) {
          _autoSyncCounter = 0;
          full = true;
        }
      }
      await _backfillSyncIds();
      if (baseline) {
        // 登录/合并后的首次同步：先拉服务端，再按差值修正计数，
        // 避免把本地全量余额重复累加到服务端。
        await _runBaselineReconcile();
      } else {
        _captureCounterDeltas();
      }
      await _pushOutbox();
      await _pushSections(full: full);
      if (!baseline) {
        await _pullChanges();
      }
      lastSyncAt.value = DateTime.now();
      await _state.put('lastSyncAt', lastSyncAt.value!.toIso8601String());
    } on FamilySyncException catch (e) {
      lastError.value = e.message;
      debugPrint('FamilySync: $e');
    } catch (e) {
      lastError.value = '同步失败: $e';
      debugPrint('FamilySync: $e');
    } finally {
      _lastSyncEndedAt = DateTime.now();
      _syncRunning = false;
      syncing.value = false;
      if (_syncQueued) {
        _syncQueued = false;
        _scheduleSync();
      }
    }
  }

  Future<void> _backfillSyncIds() async {
    for (final log in _storage.logBox.values) {
      if (log.syncId == null || log.syncId!.isEmpty) {
        log.syncId = newSyncId();
        await log.save();
      }
    }
    for (final action in _storage.actionBox.values) {
      if (action.syncId == null || action.syncId!.isEmpty) {
        action.syncId = newSyncId();
        await action.save();
      }
    }
    for (final product in _storage.productBox.values) {
      if (product.syncId == null || product.syncId!.isEmpty) {
        product.syncId = newSyncId();
        await product.save();
      }
    }
  }

  // -------------------- 计数器（操作累加） --------------------

  Map<String, Map<String, double>> _readShadow() {
    final raw = _state.get('shadow') as String? ?? '{}';
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(
        k,
        (v as Map<String, dynamic>)
            .map((f, d) => MapEntry(f, (d as num).toDouble()))));
  }

  Future<void> _writeShadow(Map<String, Map<String, double>> shadow) {
    return _state.put('shadow', jsonEncode(shadow));
  }

  List<Map<String, dynamic>> _readOps() {
    final raw = _state.get('ops') as String? ?? '[]';
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _writeOps(List<Map<String, dynamic>> ops) {
    return _state.put('ops', jsonEncode(ops));
  }

  /// 对比影子快照，把本地余额变化转成 delta 操作放入 outbox。
  ///
  /// [seedOnly] 为 true 时：只把当前余额写入影子，不生成任何 delta。
  /// 用于登录合并后的基线对账，避免把本地全量余额当成“从 0 增加”推上云端。
  void _captureCounterDeltas({bool seedOnly = false}) {
    final shadow = _readShadow();
    final ops = _readOps();
    var changed = false;
    for (final baby in _storage.babyBox.values) {
      final snap = shadow.putIfAbsent(baby.id, () => {});
      final current = <String, double>{
        'star': baby.starCount.toDouble(),
        'piggy': baby.piggyBankBalance,
        'pocket': baby.pocketMoneyBalance,
      };
      for (final entry in current.entries) {
        if (seedOnly || !snap.containsKey(entry.key)) {
          // 首次见到这个字段：建立基线，不生成 delta
          if (snap[entry.key] != entry.value) {
            snap[entry.key] = entry.value;
            changed = true;
          }
          continue;
        }
        final prev = snap[entry.key]!;
        final delta = entry.value - prev;
        if (delta.abs() > 1e-9) {
          ops.add({
            'opId': newSyncId(),
            'babyId': baby.id,
            'field': entry.key,
            'delta': delta,
          });
          snap[entry.key] = entry.value;
          changed = true;
        }
      }
    }
    if (changed) {
      _writeShadow(shadow);
      if (!seedOnly) _writeOps(ops);
    }
  }

  /// 登录 / 合并后的首次同步：
  /// 1. 先把服务端全部变更拉下来（含计数器总额）
  /// 2. 以「本地当前余额」为权威，通过 set-counters 覆盖服务端
  /// 3. 用本地余额重建影子快照，后续只推送真正的增量
  ///
  /// 这样即使合并前后本地和服务端余额不同，也不会再把本地余额当成
  /// “从 0 增加”整包累加到服务端（这正是翻倍的根因）。
  Future<void> _runBaselineReconcile() async {
    // 拉服务端最新记录与计数器
    await _pullChanges();
    // 本地余额为权威：覆盖服务端计数器
    final counters = <Map<String, dynamic>>[];
    final shadow = <String, Map<String, double>>{};
    for (final baby in _storage.babyBox.values) {
      final local = <String, double>{
        'star': baby.starCount.toDouble(),
        'piggy': baby.piggyBankBalance,
        'pocket': baby.pocketMoneyBalance,
      };
      shadow[baby.id] = Map<String, double>.from(local);
      for (final entry in local.entries) {
        counters.add({
          'babyId': baby.id,
          'field': entry.key,
          'total': entry.value,
        });
      }
    }
    if (counters.isNotEmpty) {
      await _api('POST', '/api/sync/set-counters',
          body: {'counters': counters});
    }
    await _writeShadow(shadow);
    // 清空可能残留的错误 delta
    await _writeOps([]);
    await _state.put('baselinePending', false);
  }

  /// 修复因重复累加导致的余额翻倍。
  ///
  /// 策略：用本地「星星/银行流水日志」重算每个宝宝的权威余额，
  /// 写回本地并覆盖服务端计数器。日志缺失时回退为当前本地余额。
  Future<void> repairCounterBalances() async {
    if (!enabled.value || !isLoggedIn) {
      throw FamilySyncException('请先登录家庭同步');
    }
    final rebuilt = <String, Map<String, double>>{};
    // 1) 从日志重算（star/piggy/pocket 流水；interest 进零花钱）
    for (final log in _storage.logBox.values) {
      final babyId = log.babyId;
      if (babyId.isEmpty) continue;
      final totals = rebuilt.putIfAbsent(
          babyId, () => {'star': 0, 'piggy': 0, 'pocket': 0});
      switch (log.type) {
        case 'star':
          totals['star'] = (totals['star'] ?? 0) + log.changeAmount;
          break;
        case 'piggy':
          totals['piggy'] = (totals['piggy'] ?? 0) + log.changeAmount;
          break;
        case 'pocket':
          totals['pocket'] = (totals['pocket'] ?? 0) + log.changeAmount;
          break;
        case 'interest':
          // 利息计入零花钱
          totals['pocket'] = (totals['pocket'] ?? 0) + log.changeAmount;
          break;
      }
    }

    // 2) 写回本地宝宝 + 组装 set-counters 载荷
    final counters = <Map<String, dynamic>>[];
    final shadow = _readShadow();
    _applyingRemote = true;
    try {
      for (final baby in _storage.babyBox.values) {
        final fromLogs = rebuilt[baby.id];
        // 有日志就用日志合计；没日志就保留当前本地值（避免把真实余额清零）
        final star = fromLogs != null
            ? fromLogs['star']!.round().toDouble()
            : baby.starCount.toDouble();
        final piggy =
            fromLogs != null ? fromLogs['piggy']! : baby.piggyBankBalance;
        final pocket =
            fromLogs != null ? fromLogs['pocket']! : baby.pocketMoneyBalance;

        var changed = false;
        if (baby.starCount != star.round()) {
          baby.starCount = star.round();
          changed = true;
        }
        if ((baby.piggyBankBalance - piggy).abs() > 1e-9) {
          baby.piggyBankBalance = piggy;
          changed = true;
        }
        if ((baby.pocketMoneyBalance - pocket).abs() > 1e-9) {
          baby.pocketMoneyBalance = pocket;
          changed = true;
        }
        if (changed) await baby.save();

        shadow[baby.id] = {
          'star': star,
          'piggy': piggy,
          'pocket': pocket,
        };
        counters.addAll([
          {'babyId': baby.id, 'field': 'star', 'total': star},
          {'babyId': baby.id, 'field': 'piggy', 'total': piggy},
          {'babyId': baby.id, 'field': 'pocket', 'total': pocket},
        ]);
      }
    } finally {
      _applyingRemote = false;
    }

    if (counters.isNotEmpty) {
      await _api('POST', '/api/sync/set-counters',
          body: {'counters': counters});
    }
    await _writeShadow(shadow);
    await _writeOps([]);
    await _state.put('baselinePending', false);
    _reloadControllers({'babies'});
  }

  Future<void> _pushOutbox() async {
    var ops = _readOps();
    while (ops.isNotEmpty) {
      final batch = ops.take(150).toList();
      await _api('POST', '/api/sync/push', body: {'ops': batch});
      ops = ops.skip(batch.length).toList();
      await _writeOps(ops);
    }
  }

  // -------------------- 记录与快照（哈希差异推送） --------------------

  Map<String, Map<String, String>> _readManifest() {
    final raw = _state.get('manifest') as String? ?? '{}';
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) =>
        MapEntry(k, Map<String, String>.from(v as Map<String, dynamic>)));
  }

  Future<void> _writeManifest(Map<String, Map<String, String>> manifest) {
    return _state.put('manifest', jsonEncode(manifest));
  }

  Future<void> _pushSections({required bool full}) async {
    // full=false 时只收集被标脏的数据段，避免每次同步都全量序列化+哈希。
    final targets =
        full ? _allSectionNames.toSet() : Set<String>.from(_dirtySections);
    if (targets.isEmpty) return;

    final manifest = _readManifest();
    final pending = <Map<String, dynamic>>[];
    var manifestChanged = false;

    Future<void> flush() async {
      if (pending.isEmpty) return;
      for (var i = 0; i < pending.length; i += _pushBatchSize) {
        final batch = pending.skip(i).take(_pushBatchSize).toList();
        await _api('POST', '/api/sync/push', body: {'records': batch});
      }
      pending.clear();
    }

    final now = DateTime.now().toUtc().toIso8601String();

    // 记录级数据段
    for (final section in _recordSections) {
      if (!targets.contains(section.name)) continue;
      Map<String, Map<String, dynamic>> current;
      try {
        current = await section.collect();
      } catch (e) {
        debugPrint('FamilySync: 采集 ${section.name} 失败: $e');
        continue;
      }
      final seen = manifest.putIfAbsent(section.name, () => {});
      // 新增/变化
      for (final entry in current.entries) {
        final hashSource = section.hashSource(entry.value);
        final hash = _hashPayload(hashSource);
        if (seen[entry.key] != hash) {
          final size = _canonicalJson(entry.value).length;
          if (size > _maxRecordPayloadChars) {
            debugPrint(
                'FamilySync: 跳过超大记录 ${section.name}/${entry.key} ($size chars)');
            continue;
          }
          pending.add({
            'section': section.name,
            'recordId': entry.key,
            'updatedAt': now,
            'deleted': false,
            'payload': entry.value,
          });
          seen[entry.key] = hash;
          manifestChanged = true;
        }
      }
      // 删除（清单中有、当前没有 → 墓碑）
      final removedIds =
          seen.keys.where((id) => !current.containsKey(id)).toList();
      for (final id in removedIds) {
        pending.add({
          'section': section.name,
          'recordId': id,
          'updatedAt': now,
          'deleted': true,
          'payload': null,
        });
        seen.remove(id);
        manifestChanged = true;
      }
    }

    // 快照数据段（整段一条记录）
    for (final section in _snapshotSections) {
      if (!targets.contains(section.name)) continue;
      dynamic payload;
      try {
        payload = await section.collect();
      } catch (e) {
        debugPrint('FamilySync: 采集 ${section.name} 失败: $e');
        continue;
      }
      final hash = _hashPayload(payload);
      final seen = manifest.putIfAbsent(section.name, () => {});
      if (seen['all'] != hash) {
        final size = _canonicalJson(payload).length;
        if (size > _maxSnapshotPayloadChars) {
          debugPrint('FamilySync: 跳过超大快照 ${section.name} ($size chars)');
          continue;
        }
        pending.add({
          'section': section.name,
          'recordId': 'all',
          'updatedAt': now,
          'deleted': false,
          'payload': {'data': payload},
        });
        seen['all'] = hash;
        manifestChanged = true;
      }
    }

    await flush();
    if (manifestChanged) await _writeManifest(manifest);
    // 推送成功后清除本轮处理过的脏标记
    if (_dirtySections.isNotEmpty) {
      _dirtySections.removeAll(targets);
      _persistDirty();
    }
  }

  Future<void> _pullChanges() async {
    var since = _state.get('lastSeq') as int? ?? 0;
    // 复合游标：同一批次的记录共享 seq，翻页必须带上段名+记录 ID 才不丢行
    String? sinceSection;
    String? sinceRecord;
    final manifest = _readManifest();
    var manifestChanged = false;
    var appliedAny = false;
    final appliedSections = <String>{};
    List<dynamic> counters = const [];

    while (true) {
      final data = await _api('GET', '/api/sync/changes', query: {
        'since': '$since',
        if (sinceSection != null) 'sinceSection': sinceSection,
        if (sinceRecord != null) 'sinceRecord': sinceRecord,
      });
      final records = data['records'] as List? ?? const [];
      counters = data['counters'] as List? ?? counters;

      if (records.isNotEmpty) {
        _applyingRemote = true;
        try {
          for (final raw in records) {
            final record = Map<String, dynamic>.from(raw as Map);
            final sectionName = record['section'] as String;
            final recordId = record['recordId'] as String;
            final deleted = record['deleted'] == true;
            final payload = record['payload'] == null
                ? null
                : Map<String, dynamic>.from(record['payload'] as Map);

            final recordSection =
                _recordSections.firstWhereOrNull((s) => s.name == sectionName);
            if (recordSection != null) {
              try {
                await recordSection.apply(recordId, payload, deleted);
                appliedAny = true;
                appliedSections.add(sectionName);
                final seen = manifest.putIfAbsent(sectionName, () => {});
                if (deleted) {
                  seen.remove(recordId);
                } else if (payload != null) {
                  seen[recordId] =
                      _hashPayload(recordSection.hashSource(payload));
                }
                manifestChanged = true;
              } catch (e) {
                debugPrint('FamilySync: 应用 $sectionName/$recordId 失败: $e');
              }
              continue;
            }
            final snapshotSection = _snapshotSections
                .firstWhereOrNull((s) => s.name == sectionName);
            if (snapshotSection != null && !deleted && payload != null) {
              try {
                final data = payload['data'];
                await snapshotSection.apply(data);
                appliedAny = true;
                appliedSections.add(sectionName);
                manifest.putIfAbsent(sectionName, () => {})['all'] =
                    _hashPayload(data);
                manifestChanged = true;
              } catch (e) {
                debugPrint('FamilySync: 应用快照 $sectionName 失败: $e');
              }
            }
          }
        } finally {
          _applyingRemote = false;
        }
      }

      since = (data['nextSince'] as num?)?.toInt() ?? since;
      sinceSection = data['nextSection'] as String?;
      sinceRecord = data['nextRecord'] as String?;
      if (data['hasMore'] != true) {
        final serverSeq = (data['seq'] as num?)?.toInt();
        if (serverSeq != null && serverSeq > since) since = serverSeq;
        break;
      }
    }

    await _state.put('lastSeq', since);
    if (manifestChanged) await _writeManifest(manifest);
    final countersChanged = _applyCounters(counters);
    if (appliedAny || countersChanged) {
      _reloadControllers(appliedSections);
    }
  }

  /// 服务端计数总额 + 尚未推送的本地 delta = 本地余额
  bool _applyCounters(List<dynamic> counters) {
    if (counters.isEmpty) return false;
    // 推送/拉取期间用户可能又改了余额：先把这些改动捕获成待推送
    // 操作，避免下面用服务端总额覆盖时丢失。
    _captureCounterDeltas();
    final pendingOps = _readOps();
    double pendingDelta(String babyId, String field) {
      double sum = 0;
      for (final op in pendingOps) {
        if (op['babyId'] == babyId && op['field'] == field) {
          sum += (op['delta'] as num).toDouble();
        }
      }
      return sum;
    }

    final byBaby = <String, Map<String, double>>{};
    for (final raw in counters) {
      final c = Map<String, dynamic>.from(raw as Map);
      byBaby.putIfAbsent(
              c['babyId'] as String, () => {})[c['field'] as String] =
          (c['total'] as num).toDouble();
    }

    final shadow = _readShadow();
    var anyChanged = false;
    _applyingRemote = true;
    try {
      for (final baby in _storage.babyBox.values) {
        final totals = byBaby[baby.id];
        if (totals == null) continue;
        final snap = shadow.putIfAbsent(baby.id, () => {});
        var babyChanged = false;
        void applyField(
            String field, double localValue, void Function(double v) setter) {
          final total = totals[field];
          if (total == null) return;
          final target = total + pendingDelta(baby.id, field);
          if ((localValue - target).abs() > 1e-9) {
            setter(target);
            babyChanged = true;
          }
          snap[field] = target;
        }

        applyField('star', baby.starCount.toDouble(),
            (v) => baby.starCount = v.round());
        applyField(
            'piggy', baby.piggyBankBalance, (v) => baby.piggyBankBalance = v);
        applyField('pocket', baby.pocketMoneyBalance,
            (v) => baby.pocketMoneyBalance = v);
        if (babyChanged) {
          baby.save();
          anyChanged = true;
        }
      }
    } finally {
      _applyingRemote = false;
    }
    _writeShadow(shadow);
    return anyChanged;
  }

  void _reloadControllers(Set<String> appliedSections) {
    try {
      if (Get.isRegistered<UserController>()) {
        Get.find<UserController>().reloadFromStorage();
      }
    } catch (e) {
      debugPrint('FamilySync: 刷新界面控制器失败: $e');
    }
    // 亲宝宝数据源变化才重载（其内部会全量刷新时间轴，避免无谓开销）
    if (appliedSections.contains('baby_cloud_sources') ||
        appliedSections.contains('settings')) {
      try {
        if (Get.isRegistered<BabyCloudService>()) {
          Get.find<BabyCloudService>().reloadSources();
        }
      } catch (e) {
        debugPrint('FamilySync: 刷新亲宝宝数据源失败: $e');
      }
    }
  }

  // ---------------------------------------------------------------------
  // WebDAV 备份集成：备份箱内的键由 WebDavService 直接读取；
  // 恢复时调用本方法写回配置与账号（设备本地的同步游标不恢复、重新校验）。
  // ---------------------------------------------------------------------

  static const List<String> backupConfigKeys = [
    'enabled',
    'endpoint',
    'token',
    'userId',
    'username',
    'role',
    'familyId',
    'familyName',
  ];

  Future<void> restoreConfigFromBackup(Map<String, dynamic> data) async {
    final endpointValue = data['endpoint']?.toString() ?? '';
    if (endpointValue.isEmpty) return;
    await _state.putAll({
      'enabled': data['enabled'] == true,
      'endpoint': endpointValue,
      'token': data['token']?.toString() ?? '',
      'userId': data['userId']?.toString() ?? '',
      'username': data['username']?.toString() ?? '',
      'role': data['role']?.toString() ?? '',
      'familyId': data['familyId']?.toString() ?? '',
      'familyName': data['familyName']?.toString() ?? '',
    });
    // 同步游标是设备本地状态：恢复后从零开始重新拉取校验
    await _resetSyncCursor();
    enabled.value = data['enabled'] == true;
    endpoint.value = endpointValue;
    username.value = data['username']?.toString() ?? '';
    role.value = data['role']?.toString() ?? '';
    familyName.value = data['familyName']?.toString() ?? '';
    _stopWatchers();
    _periodicTimer?.cancel();
    if (enabled.value && isLoggedIn) {
      _startWatchers();
      _startPeriodic();
      _scheduleSync();
    }
  }

  // -------------------- 首次合并的本地安全快照 --------------------

  Future<String> _writeLocalSafetySnapshot() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
        '${dir.path}${Platform.pathSeparator}family_sync_backup_${DateTime.now().millisecondsSinceEpoch}.json');
    final data = <String, dynamic>{
      'babies': _storage.babyBox.values.map((e) => e.toJson()).toList(),
      'logs': _storage.logBox.values.map((e) => e.toJson()).toList(),
      'actions': _storage.actionBox.values.map((e) => e.toJson()).toList(),
      'products': _storage.productBox.values.map((e) => e.toJson()).toList(),
      'growthRecords':
          _storage.growthRecordBox.values.map((e) => e.toJson()).toList(),
      'milestoneRecords':
          _storage.milestoneRecordBox.values.map((e) => e.toJson()).toList(),
    };
    try {
      final poopBox = await Hive.openBox<PoopRecord>('poop_records');
      data['poopRecords'] = poopBox.values.map((e) => e.toJson()).toList();
    } catch (_) {}
    await file.writeAsString(jsonEncode(data), flush: true);
    return file.path;
  }

  // -------------------- 哈希 --------------------

  String _hashPayload(dynamic payload) {
    final text = _canonicalJson(payload);
    // FNV-1a 64bit
    var hash = 0xcbf29ce484222325;
    for (final code in utf8.encode(text)) {
      hash ^= code;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  String _canonicalJson(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      final parts = keys
          .map((k) => '${jsonEncode(k)}:${_canonicalJson(value[k])}')
          .join(',');
      return '{$parts}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }

  // ---------------------------------------------------------------------
  // 数据段定义
  // ---------------------------------------------------------------------

  late final List<_RecordSection> _recordSections = [
    _RecordSection(
      name: 'babies',
      collect: () async => {
        for (final b in _storage.babyBox.values) b.id: b.toJson(),
      },
      // 余额由计数器通道同步，宝宝记录的哈希剔除余额字段，
      // 避免每次加星都触发整条宝宝记录推送/LWW 抖动。
      hashSource: (json) {
        final copy = Map<String, dynamic>.from(json);
        copy.remove('starCount');
        copy.remove('piggyBankBalance');
        copy.remove('pocketMoneyBalance');
        return copy;
      },
      apply: (id, payload, deleted) async {
        final existingKey =
            _keyOf(_storage.babyBox, (dynamic b) => (b as Baby).id == id);
        if (deleted) {
          if (existingKey != null) await _storage.babyBox.delete(existingKey);
          return;
        }
        if (payload == null) return;
        final incoming = Baby.fromJson(payload);
        if (existingKey == null) {
          await _storage.babyBox.add(incoming);
        } else {
          final local = _storage.babyBox.get(existingKey)!;
          // 保留本地余额（余额走计数器通道）
          incoming
            ..starCount = local.starCount
            ..piggyBankBalance = local.piggyBankBalance
            ..pocketMoneyBalance = local.pocketMoneyBalance;
          await _storage.babyBox.put(existingKey, incoming);
        }
      },
    ),
    _RecordSection(
      name: 'logs',
      collect: () async => {
        for (final l in _storage.logBox.values)
          if (l.syncId != null && l.syncId!.isNotEmpty) l.syncId!: l.toJson(),
      },
      apply: (id, payload, deleted) async {
        final existingKey =
            _keyOf(_storage.logBox, (dynamic l) => (l as Log).syncId == id);
        if (deleted) {
          if (existingKey != null) await _storage.logBox.delete(existingKey);
          return;
        }
        if (payload == null || existingKey != null) return;
        await _storage.logBox.add(Log.fromJson(payload));
      },
    ),
    _RecordSection(
      name: 'actions',
      collect: () async => {
        for (final a in _storage.actionBox.values)
          if (a.syncId != null && a.syncId!.isNotEmpty) a.syncId!: a.toJson(),
      },
      apply: (id, payload, deleted) async {
        final existingKey = _keyOf(
            _storage.actionBox, (dynamic a) => (a as ActionItem).syncId == id);
        if (deleted) {
          if (existingKey != null) {
            await _storage.actionBox.delete(existingKey);
          }
          return;
        }
        if (payload == null) return;
        final incoming = ActionItem.fromJson(payload);
        if (existingKey == null) {
          await _storage.actionBox.add(incoming);
        } else {
          await _storage.actionBox.put(existingKey, incoming);
        }
      },
    ),
    _RecordSection(
      name: 'products',
      collect: () async => {
        for (final p in _storage.productBox.values)
          if (p.syncId != null && p.syncId!.isNotEmpty) p.syncId!: p.toJson(),
      },
      apply: (id, payload, deleted) async {
        final existingKey = _keyOf(
            _storage.productBox, (dynamic p) => (p as Product).syncId == id);
        if (deleted) {
          if (existingKey != null) {
            await _storage.productBox.delete(existingKey);
          }
          return;
        }
        if (payload == null) return;
        final incoming = Product.fromJson(payload);
        if (existingKey == null) {
          await _storage.productBox.add(incoming);
        } else {
          await _storage.productBox.put(existingKey, incoming);
        }
      },
    ),
    _RecordSection(
      name: 'growth_records',
      collect: () async => {
        for (final g in _storage.growthRecordBox.values) g.id: g.toJson(),
      },
      apply: (id, payload, deleted) async {
        final existingKey = _keyOf(_storage.growthRecordBox,
            (dynamic g) => (g as GrowthRecord).id == id);
        if (deleted) {
          if (existingKey != null) {
            await _storage.growthRecordBox.delete(existingKey);
          }
          return;
        }
        if (payload == null) return;
        final incoming = GrowthRecord.fromJson(payload);
        if (existingKey == null) {
          await _storage.growthRecordBox.add(incoming);
        } else {
          await _storage.growthRecordBox.put(existingKey, incoming);
        }
      },
    ),
    _RecordSection(
      name: 'milestone_records',
      collect: () async => {
        for (final m in _storage.milestoneRecordBox.values) m.id: m.toJson(),
      },
      apply: (id, payload, deleted) async {
        final existingKey = _keyOf(_storage.milestoneRecordBox,
            (dynamic m) => (m as MilestoneRecord).id == id);
        if (deleted) {
          if (existingKey != null) {
            await _storage.milestoneRecordBox.delete(existingKey);
          }
          return;
        }
        if (payload == null) return;
        final incoming = MilestoneRecord.fromJson(payload);
        if (existingKey == null) {
          await _storage.milestoneRecordBox.add(incoming);
        } else {
          await _storage.milestoneRecordBox.put(existingKey, incoming);
        }
      },
    ),
    _RecordSection(
      name: 'poop_records',
      collect: () async {
        try {
          final box = await Hive.openBox<PoopRecord>('poop_records');
          return {for (final p in box.values) p.id: p.toJson()};
        } catch (_) {
          return {};
        }
      },
      apply: (id, payload, deleted) async {
        final box = await Hive.openBox<PoopRecord>('poop_records');
        if (deleted) {
          // 便便记录以 id 作为 Hive key 存储
          await box.delete(id);
          return;
        }
        if (payload == null) return;
        await box.put(id, PoopRecord.fromJson(payload));
      },
    ),
    _RecordSection(
      name: 'baby_cloud_sources',
      collect: () async => {
        for (final s in _storage.babyCloudSourceBox.values) s.id: s.toJson(),
      },
      apply: (id, payload, deleted) async {
        // 数据源盒以 id 作为 Hive key 存储
        if (deleted) {
          await _storage.babyCloudSourceBox.delete(id);
          return;
        }
        if (payload == null) return;
        await _storage.babyCloudSourceBox
            .put(id, BabyCloudSource.fromJson(payload));
      },
    ),
    _RecordSection(
      name: 'ai_chats',
      collect: () async {
        try {
          final box = await Hive.openBox<dynamic>('ai_chats');
          final result = <String, Map<String, dynamic>>{};
          for (final e in box.values) {
            try {
              final chat = e as AIChat;
              result[chat.id] = chat.toJson();
            } catch (_) {}
          }
          return result;
        } catch (_) {
          return {};
        }
      },
      apply: (id, payload, deleted) async {
        final box = await Hive.openBox<dynamic>('ai_chats');
        final key = _keyOf(box, (dynamic c) {
          try {
            return (c as AIChat).id == id;
          } catch (_) {
            return false;
          }
        });
        if (deleted) {
          if (key != null) await box.delete(key);
          return;
        }
        if (payload == null) return;
        final incoming = AIChat.fromJson(payload);
        if (key == null) {
          await box.add(incoming);
        } else {
          await box.put(key, incoming);
        }
      },
    ),
    _RecordSection(
      name: 'story_sessions',
      collect: () async {
        try {
          final box = await Hive.openBox<dynamic>('story_sessions');
          final result = <String, Map<String, dynamic>>{};
          for (final e in box.values) {
            try {
              final session = e as StorySession;
              result[session.id] = session.toJson();
            } catch (_) {}
          }
          return result;
        } catch (_) {
          return {};
        }
      },
      apply: (id, payload, deleted) async {
        final box = await Hive.openBox<dynamic>('story_sessions');
        final key = _keyOf(box, (dynamic s) {
          try {
            return (s as StorySession).id == id;
          } catch (_) {
            return false;
          }
        });
        if (deleted) {
          if (key != null) await box.delete(key);
          return;
        }
        if (payload == null) return;
        final incoming = StorySession.fromJson(payload);
        if (key == null) {
          await box.add(incoming);
        } else {
          await box.put(key, incoming);
        }
      },
    ),
  ];

  late final List<_SnapshotSection> _snapshotSections = [
    _SnapshotSection(
      name: 'settings',
      collect: () async {
        final result = <String, dynamic>{};
        for (final entry in _storage.settingsBox.toMap().entries) {
          final key = entry.key.toString();
          if (WebDavBackupV2Service.shouldBackupGenericSetting(key) ||
              _extraSettingsKeys.contains(key)) {
            result[key] = entry.value;
          }
        }
        return result;
      },
      apply: (data) async {
        if (data is! Map) return;
        for (final entry in data.entries) {
          final key = entry.key.toString();
          if (WebDavBackupV2Service.shouldBackupGenericSetting(key) ||
              _extraSettingsKeys.contains(key)) {
            await _storage.settingsBox.put(key, entry.value);
          }
        }
      },
    ),
    _SnapshotSection(
      name: 'user_profile',
      collect: () async =>
          _storage.userBox.values.map((e) => e.toJson()).toList(),
      apply: (data) async {
        if (data is! List || data.isEmpty) return;
        await _storage.userBox.clear();
        for (final item in data) {
          await _storage.userBox.add(
              UserProfile.fromJson(Map<String, dynamic>.from(item as Map)));
        }
      },
    ),
    for (final boxName in const [
      'tts_settings',
      'poop_ai_settings',
      'growth_record_settings',
      'milestone_record_settings',
      'story_game_config',
      'hanzi_learning_config',
    ])
      _SnapshotSection(
        name: boxName,
        collect: () async {
          try {
            final box = await Hive.openBox(boxName);
            return Map<String, dynamic>.from(
                box.toMap().map((k, v) => MapEntry(k.toString(), v)));
          } catch (_) {
            return <String, dynamic>{};
          }
        },
        apply: (data) async {
          if (data is! Map) return;
          final box = await Hive.openBox(boxName);
          await box.clear();
          for (final entry in data.entries) {
            await box.put(entry.key.toString(), entry.value);
          }
        },
      ),
    _SnapshotSection(
      name: 'openai_configs',
      collect: () async {
        try {
          final box = await Hive.openBox<OpenAIConfig>('openai_configs');
          return box.values.map((e) => e.toJson()).toList();
        } catch (_) {
          return <dynamic>[];
        }
      },
      apply: (data) async {
        if (data is! List) return;
        final box = await Hive.openBox<OpenAIConfig>('openai_configs');
        await box.clear();
        for (final item in data) {
          await box.add(
              OpenAIConfig.fromJson(Map<String, dynamic>.from(item as Map)));
        }
      },
    ),
    _SnapshotSection(
      name: 'cftts_config',
      collect: () async {
        try {
          final box = await Hive.openBox<CfttsConfig>('cftts_config_box');
          return box.values.map((e) => e.toJson()).toList();
        } catch (_) {
          return <dynamic>[];
        }
      },
      apply: (data) async {
        if (data is! List) return;
        final box = await Hive.openBox<CfttsConfig>('cftts_config_box');
        await box.clear();
        for (final item in data) {
          await box.add(
              CfttsConfig.fromJson(Map<String, dynamic>.from(item as Map)));
        }
      },
    ),
    _SnapshotSection(
      name: 'openai_tts_config',
      collect: () async {
        try {
          final box =
              await Hive.openBox<OpenAITtsConfig>('openai_tts_config_box');
          return box.values.map((e) => e.toJson()).toList();
        } catch (_) {
          return <dynamic>[];
        }
      },
      apply: (data) async {
        if (data is! List) return;
        final box =
            await Hive.openBox<OpenAITtsConfig>('openai_tts_config_box');
        await box.clear();
        for (final item in data) {
          await box.add(
              OpenAITtsConfig.fromJson(Map<String, dynamic>.from(item as Map)));
        }
      },
    ),
    _SnapshotSection(
      name: 'quiz',
      collect: () async {
        if (!Get.isRegistered<QuizService>()) return <String, dynamic>{};
        final quiz = Get.find<QuizService>();
        return {
          // 直接导出题目 JSON：AI 生成的图片不做 base64 内联、不参与同步
          'questions': quiz.questions.map((q) => q.toJson()).toList(),
          if (quiz.config.value != null) 'config': quiz.config.value!.toJson(),
        };
      },
      apply: (data) async {
        if (data is! Map || !Get.isRegistered<QuizService>()) return;
        await Get.find<QuizService>()
            .importData(Map<String, dynamic>.from(data));
      },
    ),
    _SnapshotSection(
      name: 'encyclopedia',
      collect: () async {
        if (!Get.isRegistered<EncyclopediaService>()) {
          return <String, dynamic>{};
        }
        final data = await Get.find<EncyclopediaService>().exportData();
        data.remove('explanationCaches');
        // 游玩记录单独一段同步，避免它的频繁变化导致题库整段重传
        data.remove('playRecords');
        return data;
      },
      apply: (data) async {
        if (data is! Map || !Get.isRegistered<EncyclopediaService>()) return;
        await Get.find<EncyclopediaService>()
            .importData(Map<String, dynamic>.from(data));
      },
    ),
    _SnapshotSection(
      name: 'encyclopedia_play',
      collect: () async {
        if (!Get.isRegistered<EncyclopediaService>()) {
          return <String, dynamic>{};
        }
        final data = await Get.find<EncyclopediaService>().exportData();
        return {'playRecords': data['playRecords'] ?? <String, dynamic>{}};
      },
      apply: (data) async {
        if (data is! Map || !Get.isRegistered<EncyclopediaService>()) return;
        await Get.find<EncyclopediaService>()
            .importData({'playRecords': data['playRecords']});
      },
    ),
    _SnapshotSection(
      name: 'new_year_stories',
      collect: () async {
        try {
          // 直接导出故事记录，插图保持本地路径，不做 base64 内联
          return StoryManagementService.instance
              .getAllStories()
              .map((s) => s.toJson())
              .toList();
        } catch (_) {
          return <dynamic>[];
        }
      },
      apply: (data) async {
        if (data is! List) return;
        await StoryManagementService.instance.restoreStories(data);
      },
    ),
    _SnapshotSection(
      name: 'custom_riddles',
      collect: () async {
        try {
          final box = await Hive.openBox('custom_riddles');
          return box.values.toList();
        } catch (_) {
          return <dynamic>[];
        }
      },
      apply: (data) async {
        if (data is! List) return;
        final box = await Hive.openBox('custom_riddles');
        await box.clear();
        for (final item in data) {
          await box.add(item);
        }
      },
    ),
  ];

  dynamic _keyOf(Box box, bool Function(dynamic) test) {
    for (final key in box.keys) {
      final value = box.get(key);
      if (value != null && test(value)) return key;
    }
    return null;
  }
}

enum FirstLoginResult { done, needMergeChoice }

class FamilySyncException implements Exception {
  FamilySyncException(this.message);
  final String message;
  @override
  String toString() => 'FamilySyncException: $message';
}

class _RecordSection {
  _RecordSection({
    required this.name,
    required this.collect,
    required this.apply,
    Map<String, dynamic> Function(Map<String, dynamic>)? hashSource,
  }) : hashSource = hashSource ?? _identity;

  static Map<String, dynamic> _identity(Map<String, dynamic> json) => json;

  final String name;
  final Future<Map<String, Map<String, dynamic>>> Function() collect;
  final Future<void> Function(
      String id, Map<String, dynamic>? payload, bool deleted) apply;
  final Map<String, dynamic> Function(Map<String, dynamic>) hashSource;
}

class _SnapshotSection {
  _SnapshotSection({
    required this.name,
    required this.collect,
    required this.apply,
  });

  final String name;
  final Future<dynamic> Function() collect;
  final Future<void> Function(dynamic data) apply;
}
