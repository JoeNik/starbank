import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/app_mode_controller.dart';
import '../../controllers/user_controller.dart';
import '../../models/baby_cloud_source.dart';
import '../../services/baby_cloud_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/toast_utils.dart';

String _normalizeWebDavEndpointMode(String? mode) {
  final value = mode?.trim().toLowerCase();
  if (value == 'lan' || value == 'external') return value!;
  return 'auto';
}

String _endpointModeLabel(String mode) {
  switch (_normalizeWebDavEndpointMode(mode)) {
    case 'lan':
      return '固定内网';
    case 'external':
      return '固定外网';
    default:
      return '自动检测';
  }
}

class BabyCloudSourcePage extends StatefulWidget {
  const BabyCloudSourcePage({super.key});

  @override
  State<BabyCloudSourcePage> createState() => _BabyCloudSourcePageState();
}

class _BabyCloudSourcePageState extends State<BabyCloudSourcePage> {
  final _cloud = Get.find<BabyCloudService>();
  final _storage = Get.find<StorageService>();
  final _mode = Get.find<AppModeController>();
  final _user = Get.find<UserController>();
  final _checkingIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('亲宝宝数据源'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: '查看云端宝宝目录',
            onPressed: _showRemoteBabyDirs,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加数据源',
            onPressed: () {
              if (!_mode.isParentMode) {
                ToastUtils.showWarning('请先切换到家长模式后再添加数据源');
                return;
              }
              _showSourceEditor();
            },
          ),
        ],
      ),
      body: Obx(() {
        if (_cloud.sources.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(28.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_sync_outlined,
                    size: 60.sp,
                    color: Colors.pink.shade200,
                  ),
                  SizedBox(height: 14.h),
                  Text(
                    '还没有亲宝宝数据源',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    '配置 WebDAV 或阿里云盘数据源后，云相册会把照片和视频加入后台任务队列。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                  SizedBox(height: 18.h),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (!_mode.isParentMode) {
                        ToastUtils.showWarning('请先切换到家长模式后再添加数据源');
                        return;
                      }
                      _showSourceEditor();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('添加数据源'),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: EdgeInsets.all(16.w),
          itemCount: _cloud.sources.length,
          separatorBuilder: (_, __) => SizedBox(height: 12.h),
          itemBuilder: (_, index) {
            final source = _cloud.sources[index];
            final selected = source.id == _cloud.currentSource.value?.id;
            return _SourceCard(
              source: source,
              selected: selected,
              checking: _checkingIds.contains(source.id),
              onModeChanged: source.isWebDav
                  ? (mode) => _changeSourceMode(source, mode)
                  : null,
              onSelect: () async {
                if (!_mode.isParentMode) {
                  ToastUtils.showWarning('请先切换到家长模式后再切换数据源');
                  return;
                }
                await _cloud.selectSource(source.id);
                ToastUtils.showSuccess('已切换到 ${source.name}');
                await _promptSyncAfterSwitch();
              },
              onCheck: () => _manualCheckSource(source),
              onEdit: () {
                if (!_mode.isParentMode) {
                  ToastUtils.showWarning('请先切换到家长模式后再编辑数据源');
                  return;
                }
                _showSourceEditor(source: source);
              },
              onDirectory: () => _openRootPickerForSource(source),
            );
          },
        );
      }),
    );
  }

  Future<void> _manualCheckSource(BabyCloudSource source) async {
    if (!_mode.isParentMode) {
      ToastUtils.showWarning('请先切换到家长模式后再检测数据源');
      return;
    }
    if (_checkingIds.contains(source.id)) {
      ToastUtils.showInfo('正在检测 ${source.name}，请稍等');
      return;
    }
    setState(() => _checkingIds.add(source.id));
    ToastUtils.showInfo('正在检测 ${source.name}');
    try {
      final result = await _cloud.checkSource(source);
      if (result.ok) {
        if (source.isWebDav) {
          ToastUtils.showSuccess('已连接${result.endpointLabel} WebDAV');
        } else {
          ToastUtils.showSuccess('${source.name} 可用');
        }
      } else {
        ToastUtils.showError(result.message);
      }
    } finally {
      if (mounted) setState(() => _checkingIds.remove(source.id));
    }
  }

  Future<void> _promptSyncAfterSwitch() async {
    final baby = _user.currentBaby.value;
    if (baby == null) return;
    final sync = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('同步远端数据？'),
        content: const Text(
          '将读取当前数据源的亲宝宝云端目录，并与本地数据合并。此操作不会删除本地数据，也不会物理删除云端文件。',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('立即同步'),
          ),
        ],
      ),
    );
    if (sync == true) {
      await _cloud.syncBaby(
        baby,
        showErrors: true,
        forceRemote: true,
      );
    }
  }

  Future<void> _showSourceEditor({BabyCloudSource? source}) async {
    if (!_mode.isParentMode) {
      ToastUtils.showWarning('请先切换到家长模式后再修改数据源');
      return;
    }
    final item = await Navigator.of(context).push<BabyCloudSource>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _BabyCloudSourceEditorPage(
          source: source,
          onPickRoot: (editorContext, temp, rootText) async {
            if (!_hasRequiredSourceInput(temp)) {
              ToastUtils.showWarning('请先完善数据源连接信息');
              return null;
            }
            final picked = await _showDirectoryPicker(
              temp,
              initialPath: _pickerPathFromRoot(rootText),
              persistCheck: false,
              hostContext: editorContext,
            );
            return picked == null ? null : _rootTextFromPickedPath(picked);
          },
        ),
      ),
    );
    if (item == null || !mounted) return;
    await _cloud.saveSource(item);
    await _manualCheckSource(item);
  }

  Future<void> _changeSourceMode(
    BabyCloudSource source,
    String mode,
  ) async {
    if (!_mode.isParentMode) {
      ToastUtils.showWarning('请先切换到家长模式后再切换检测方式');
      return;
    }
    final normalizedMode = _normalizeWebDavEndpointMode(mode);
    if (!source.isWebDav ||
        _normalizeWebDavEndpointMode(source.webDavEndpointMode) ==
            normalizedMode) {
      return;
    }
    source
      ..webDavEndpointMode = normalizedMode
      ..activeWebDavUrl = null
      ..activeWebDavEndpoint = 'none'
      ..status = 'notInitialized';
    await _cloud.saveSource(source);
    if (!mounted) return;
    ToastUtils.showSuccess('已切换为${_endpointModeLabel(normalizedMode)}，正在重新检测');
    await _manualCheckSource(source);
  }

  bool _hasRequiredSourceInput(BabyCloudSource source) {
    if (source.isAliyunDrive) {
      return source.aliyunDriveClientId?.trim().isNotEmpty == true ||
          source.aliyunDriveAccessToken?.trim().isNotEmpty == true ||
          source.aliyunDriveRefreshToken?.trim().isNotEmpty == true;
    }
    final mode = _normalizeWebDavEndpointMode(source.webDavEndpointMode);
    if (mode == 'lan') {
      return source.webDavLanUrl?.trim().isNotEmpty == true;
    }
    if (mode == 'external') {
      return source.webDavUrl?.trim().isNotEmpty == true;
    }
    return (source.webDavUrl?.trim().isNotEmpty ?? false) ||
        (source.webDavLanUrl?.trim().isNotEmpty ?? false);
  }

  Future<void> _openRootPickerForSource(BabyCloudSource source) async {
    if (!_mode.isParentMode) {
      ToastUtils.showWarning('请先切换到家长模式，儿童模式不能修改云端目录');
      return;
    }
    final picked = await _showDirectoryPicker(
      source,
      initialPath: _pickerPathFromRoot(source.rootPath),
    );
    if (picked == null) return;
    source
      ..rootPath = _rootTextFromPickedPath(picked)
      ..status = 'notInitialized'
      ..activeWebDavUrl = null
      ..activeWebDavEndpoint = 'none';
    await _cloud.saveSource(source);
    ToastUtils.showSuccess('亲宝宝根目录已更新');
    await _manualCheckSource(source);
  }

  Future<String?> _showDirectoryPicker(
    BabyCloudSource source, {
    required String initialPath,
    bool persistCheck = true,
    BuildContext? hostContext,
  }) {
    return showModalBottomSheet<String>(
      context: hostContext ?? context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WebDavDirectoryPicker(
        source: source,
        initialPath: initialPath,
        persistCheck: persistCheck,
      ),
    );
  }

  String _pickerPathFromRoot(String root) {
    final value = root.trim().replaceAll('\\', '/');
    if (value.isEmpty) return '/starbank_baby_cloud';
    return value.startsWith('/') ? value : '/$value';
  }

  String _rootTextFromPickedPath(String path) {
    if (path == '/') return '/';
    return path.replaceFirst(RegExp(r'^/+'), '');
  }

  Future<void> _showRemoteBabyDirs() async {
    if (!_mode.isParentMode) {
      ToastUtils.showWarning('请先切换到家长模式，儿童模式不能管理云端目录');
      return;
    }
    final source = _cloud.currentSource.value;
    if (source == null) {
      ToastUtils.showWarning('请先选择一个亲宝宝数据源');
      return;
    }
    try {
      ToastUtils.showInfo('正在读取云端宝宝目录');
      final dirs = await _cloud.listRemoteBabyDirs(source);
      final localBabyIds = _storage.babyBox.values.map((b) => b.id).toSet();
      await Get.to(
        () => _RemoteBabyDirPage(
          dirs: dirs,
          localBabyIds: localBabyIds,
        ),
      );
    } catch (e) {
      ToastUtils.showError('读取云端目录失败: $e');
    }
  }
}

typedef _PickBabyCloudRoot = Future<String?> Function(
  BuildContext context,
  BabyCloudSource temp,
  String rootText,
);

class _BabyCloudSourceEditorPage extends StatefulWidget {
  const _BabyCloudSourceEditorPage({
    required this.source,
    required this.onPickRoot,
  });

  final BabyCloudSource? source;
  final _PickBabyCloudRoot onPickRoot;

  @override
  State<_BabyCloudSourceEditorPage> createState() =>
      _BabyCloudSourceEditorPageState();
}

class _BabyCloudSourceEditorPageState
    extends State<_BabyCloudSourceEditorPage> {
  final _cloud = Get.find<BabyCloudService>();

  late final String _sourceId;
  late String _type;
  late final TextEditingController _name;
  late final TextEditingController _externalUrl;
  late final TextEditingController _lanUrl;
  late final TextEditingController _user;
  late final TextEditingController _password;
  late final TextEditingController _aliyunClientId;
  late final TextEditingController _aliyunClientSecret;
  late final TextEditingController _aliyunRedirectUri;
  late final TextEditingController _aliyunScope;
  late final TextEditingController _aliyunAuthUrl;
  late final TextEditingController _aliyunTokenUrl;
  late final TextEditingController _aliyunRefreshToken;
  late final TextEditingController _aliyunAccessToken;
  late final TextEditingController _root;

  final _nameFocus = FocusNode();
  final _externalFocus = FocusNode();
  final _lanFocus = FocusNode();
  final _userFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _aliyunClientIdFocus = FocusNode();
  final _aliyunFocus = FocusNode();
  final _rootFocus = FocusNode();
  bool _aliyunAuthorizing = false;
  late String _webDavEndpointMode;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _sourceId = source?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    _type = source?.type ?? 'webdav';
    _webDavEndpointMode = _normalizeWebDavEndpointMode(
      source?.webDavEndpointMode,
    );
    _name = TextEditingController(text: source?.name ?? '亲宝宝 WebDAV');
    _externalUrl = TextEditingController(text: source?.webDavUrl ?? '');
    _lanUrl = TextEditingController(text: source?.webDavLanUrl ?? '');
    _user = TextEditingController(text: source?.webDavUsername ?? '');
    _password = TextEditingController(text: source?.webDavPassword ?? '');
    _aliyunClientId = TextEditingController(
      text: source?.aliyunDriveClientId ?? '',
    );
    _aliyunClientSecret = TextEditingController(
      text: source?.aliyunDriveClientSecret ?? '',
    );
    _aliyunRedirectUri = TextEditingController(
      text: source?.aliyunDriveRedirectUri ??
          BabyCloudService.aliyunDriveDefaultRedirectUri,
    );
    _aliyunScope = TextEditingController(
      text:
          source?.aliyunDriveScope ?? BabyCloudService.aliyunDriveDefaultScope,
    );
    _aliyunAuthUrl = TextEditingController(
      text: source?.aliyunDriveAuthUrl ??
          BabyCloudService.aliyunDriveDefaultAuthUrl,
    );
    _aliyunTokenUrl = TextEditingController(
      text: source?.aliyunDriveTokenUrl ??
          BabyCloudService.aliyunDriveDefaultTokenUrl,
    );
    _aliyunRefreshToken = TextEditingController(
      text: source?.aliyunDriveRefreshToken ?? '',
    );
    _aliyunAccessToken = TextEditingController(
      text: source?.aliyunDriveAccessToken ?? '',
    );
    _root = TextEditingController(
      text: source?.rootPath ?? 'starbank_baby_cloud',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _externalUrl.dispose();
    _lanUrl.dispose();
    _user.dispose();
    _password.dispose();
    _aliyunClientId.dispose();
    _aliyunClientSecret.dispose();
    _aliyunRedirectUri.dispose();
    _aliyunScope.dispose();
    _aliyunAuthUrl.dispose();
    _aliyunTokenUrl.dispose();
    _aliyunRefreshToken.dispose();
    _aliyunAccessToken.dispose();
    _root.dispose();
    _nameFocus.dispose();
    _externalFocus.dispose();
    _lanFocus.dispose();
    _userFocus.dispose();
    _passwordFocus.dispose();
    _aliyunClientIdFocus.dispose();
    _aliyunFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(widget.source == null ? '添加数据源' : '编辑数据源'),
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 24.h),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            children: [
              Text(
                '这套配置只服务亲宝宝云相册，不会影响设置里的主 WebDAV 备份。',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey.shade700,
                  height: 1.35,
                ),
              ),
              SizedBox(height: 18.h),
              _buildTypeSelector(),
              SizedBox(height: 12.h),
              TextField(
                controller: _name,
                focusNode: _nameFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _type == 'webdav'
                    ? _externalFocus.requestFocus()
                    : _aliyunClientIdFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 12.h),
              if (_type == 'webdav') ..._buildWebDavFields(),
              if (_type == 'aliyunDrive') ..._buildAliyunDriveFields(),
              _buildRootField(),
              SizedBox(height: 18.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: const Text('保存并检测'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    final locked = widget.source != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '数据源类型',
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            ChoiceChip(
              label: const Text('WebDAV'),
              avatar: const Icon(Icons.cloud_queue, size: 18),
              selected: _type == 'webdav',
              onSelected: locked ? null : (_) => _setType('webdav'),
            ),
            ChoiceChip(
              label: const Text('阿里云盘'),
              avatar: const Icon(Icons.cloud_outlined, size: 18),
              selected: _type == 'aliyunDrive',
              onSelected: locked ? null : (_) => _setType('aliyunDrive'),
            ),
          ],
        ),
        if (locked) ...[
          SizedBox(height: 6.h),
          Text(
            '已有数据源类型不可直接切换，请新建对应类型的数据源。',
            style: TextStyle(fontSize: 11.sp, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildWebDavFields() {
    return [
      Text(
        '连接模式',
        style: TextStyle(
          fontSize: 12.sp,
          color: Colors.grey.shade700,
          fontWeight: FontWeight.w700,
        ),
      ),
      SizedBox(height: 8.h),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment<String>(
            value: 'auto',
            label: Text('自动'),
            icon: Icon(Icons.auto_awesome_outlined),
          ),
          ButtonSegment<String>(
            value: 'lan',
            label: Text('内网'),
            icon: Icon(Icons.wifi),
          ),
          ButtonSegment<String>(
            value: 'external',
            label: Text('外网'),
            icon: Icon(Icons.public),
          ),
        ],
        selected: {_webDavEndpointMode},
        onSelectionChanged: (selection) {
          if (selection.isEmpty) return;
          setState(() {
            _webDavEndpointMode = selection.first;
          });
        },
      ),
      SizedBox(height: 8.h),
      Text(
        _webDavEndpointMode == 'auto'
            ? '默认自动检测当前网络环境，优先选择更合适的地址。'
            : _webDavEndpointMode == 'lan'
                ? '手动固定走内网地址，适合家里 WiFi 测试不稳定时使用。'
                : '手动固定走外网地址，不再自动尝试内网。',
        style: TextStyle(
          fontSize: 11.sp,
          color: Colors.grey.shade600,
          height: 1.35,
        ),
      ),
      SizedBox(height: 12.h),
      TextField(
        controller: _externalUrl,
        focusNode: _externalFocus,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _lanFocus.requestFocus(),
        decoration: const InputDecoration(
          labelText: '外网 WebDAV 地址',
          hintText: 'http://example.com/dav 或 https://example.com/dav',
          helperText: '离开家里 WiFi 时使用，支持 HTTP 和 HTTPS',
          border: OutlineInputBorder(),
        ),
      ),
      SizedBox(height: 12.h),
      TextField(
        controller: _lanUrl,
        focusNode: _lanFocus,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _userFocus.requestFocus(),
        decoration: const InputDecoration(
          labelText: '内网 WebDAV 地址（可选）',
          hintText: 'http://192.168.1.10:5005/dav',
          helperText: '连接局域网时优先检测，支持非 HTTPS',
          border: OutlineInputBorder(),
        ),
      ),
      SizedBox(height: 12.h),
      TextField(
        controller: _user,
        focusNode: _userFocus,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.username],
        onSubmitted: (_) => _passwordFocus.requestFocus(),
        decoration: const InputDecoration(
          labelText: '用户名',
          border: OutlineInputBorder(),
        ),
      ),
      SizedBox(height: 12.h),
      TextField(
        controller: _password,
        focusNode: _passwordFocus,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) => _rootFocus.requestFocus(),
        decoration: const InputDecoration(
          labelText: '密码',
          border: OutlineInputBorder(),
        ),
      ),
      SizedBox(height: 12.h),
    ];
  }

  List<Widget> _buildAliyunDriveFields() {
    return [
      Container(
        width: double.infinity,
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: Colors.blueGrey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OAuth 登录',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w800,
                color: Colors.blueGrey.shade900,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              '必填要素是 Client ID 和回调地址。登录会打开浏览器，成功后通过回调地址回到 App；没有自动回跳时可粘贴 code。',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.blueGrey.shade700,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: 12.h),
      TextField(
        controller: _aliyunClientId,
        focusNode: _aliyunClientIdFocus,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _aliyunFocus.requestFocus(),
        decoration: const InputDecoration(
          labelText: 'Client ID',
          helperText: '阿里云盘开放平台应用的 Client ID',
          border: OutlineInputBorder(),
        ),
      ),
      SizedBox(height: 12.h),
      TextField(
        controller: _aliyunRedirectUri,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Redirect URI',
          helperText: '开放平台里配置同样的地址，默认可回跳 App',
          border: OutlineInputBorder(),
        ),
      ),
      SizedBox(height: 12.h),
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _aliyunAuthorizing ? null : _startAliyunOAuth,
              icon: _aliyunAuthorizing
                  ? SizedBox(
                      width: 16.w,
                      height: 16.w,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_browser),
              label: const Text('浏览器授权'),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _aliyunAuthorizing ? null : _pasteAliyunOAuthCode,
              icon: const Icon(Icons.content_paste),
              label: const Text('粘贴 code'),
            ),
          ),
        ],
      ),
      SizedBox(height: 16.h),
      Container(
        width: double.infinity,
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: Colors.green.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '令牌登录',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w800,
                color: Colors.green.shade900,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              '可像 OpenList 一样直接填写令牌。Access Token 可立即校验和使用；Refresh Token 可自动换新，但通常仍需要 Client ID。',
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.green.shade900,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: 12.h),
      TextField(
        controller: _aliyunAccessToken,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.next,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Access Token',
          helperText: '直接使用当前令牌；过期后需要重新填写或改用 OAuth',
          border: OutlineInputBorder(),
        ),
      ),
      SizedBox(height: 12.h),
      TextField(
        controller: _aliyunRefreshToken,
        focusNode: _aliyunFocus,
        keyboardType: TextInputType.visiblePassword,
        textInputAction: TextInputAction.next,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        onSubmitted: (_) => _rootFocus.requestFocus(),
        decoration: const InputDecoration(
          labelText: 'Refresh Token',
          helperText: 'OAuth 成功后自动写入；也可粘贴已有 refresh token',
          border: OutlineInputBorder(),
        ),
      ),
      SizedBox(height: 12.h),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('高级设置'),
        subtitle: const Text('Client Secret、scope 和 OAuth 端点'),
        childrenPadding: EdgeInsets.zero,
        children: [
          TextField(
            controller: _aliyunClientSecret,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.next,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Client Secret（可选）',
              helperText: '移动端不建议硬编码密钥；开放平台要求时再填写',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 12.h),
          TextField(
            controller: _aliyunScope,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Scope',
              helperText: '按开放平台审核结果填写，多个 scope 用逗号分隔',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 12.h),
          TextField(
            controller: _aliyunAuthUrl,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '授权地址',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 12.h),
          TextField(
            controller: _aliyunTokenUrl,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Token 地址',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 12.h),
        ],
      ),
      SizedBox(height: 12.h),
    ];
  }

  Widget _buildRootField() {
    return TextField(
      controller: _root,
      focusNode: _rootFocus,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: _type == 'webdav' ? '亲宝宝云端根目录' : '云端根目录名',
        helperText: _type == 'webdav'
            ? '不同宝宝会自动放到这个目录下的不同子目录'
            : '会在阿里云盘中创建或定位这个应用目录',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: '选择云端目录',
          icon: const Icon(Icons.folder_open_outlined),
          onPressed: _pickRoot,
        ),
      ),
    );
  }

  void _setType(String type) {
    if (_type == type) return;
    final oldDefault = _type == 'webdav' ? '亲宝宝 WebDAV' : '阿里云盘';
    setState(() {
      _type = type;
      if (_name.text.trim().isEmpty || _name.text.trim() == oldDefault) {
        _name.text = type == 'webdav' ? '亲宝宝 WebDAV' : '阿里云盘';
      }
    });
  }

  Future<void> _startAliyunOAuth() async {
    final source = _sourceFromInput();
    setState(() => _aliyunAuthorizing = true);
    try {
      await _cloud.startAliyunDriveOAuth(source);
      ToastUtils.showInfo('已打开浏览器，登录授权后会自动回到 App');
    } catch (e) {
      ToastUtils.showError('启动阿里云盘授权失败: $e');
    } finally {
      if (mounted) setState(() => _aliyunAuthorizing = false);
    }
  }

  Future<void> _pasteAliyunOAuthCode() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('粘贴授权 code'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '可粘贴完整回调链接，或只粘贴 code',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (input == null || input.trim().isEmpty) return;

    final source = _sourceFromInput();
    setState(() => _aliyunAuthorizing = true);
    try {
      final result = await _cloud.completeAliyunOAuthWithInput(source, input);
      if (result.ok) {
        final stored = _storedSource();
        _aliyunRefreshToken.text =
            stored?.aliyunDriveRefreshToken ?? _aliyunRefreshToken.text;
        _aliyunAccessToken.text =
            stored?.aliyunDriveAccessToken ?? _aliyunAccessToken.text;
        ToastUtils.showSuccess('阿里云盘授权成功');
      } else {
        ToastUtils.showError(result.message);
      }
    } catch (e) {
      ToastUtils.showError('完成阿里云盘授权失败: $e');
    } finally {
      if (mounted) setState(() => _aliyunAuthorizing = false);
    }
  }

  Future<void> _pickRoot() async {
    final temp = _sourceFromInput();
    if (!_hasRequiredSourceInput(temp)) {
      ToastUtils.showWarning(
        temp.isAliyunDrive
            ? '请先完成阿里云盘授权，或填写 Access Token'
            : '请先填写至少一个 WebDAV 地址',
      );
      return;
    }
    final picked = await widget.onPickRoot(context, temp, _root.text);
    if (picked == null || !mounted) return;
    _root.value = TextEditingValue(
      text: picked,
      selection: TextSelection.collapsed(offset: picked.length),
    );
  }

  void _submit() {
    final item = _sourceFromInput();
    if (!_hasRequiredSourceInput(item)) {
      ToastUtils.showWarning(
        item.isAliyunDrive
            ? '请先填写阿里云盘 Client ID 或可用令牌'
            : item.webDavEndpointMode == 'lan'
                ? '固定内网模式下请填写内网 WebDAV 地址'
                : item.webDavEndpointMode == 'external'
                    ? '固定外网模式下请填写外网 WebDAV 地址'
                    : '请至少填写外网或内网 WebDAV 地址',
      );
      return;
    }
    Navigator.of(context).pop(item);
  }

  BabyCloudSource _sourceFromInput() {
    final source = widget.source;
    final stored = _storedSource();
    final rootText = _root.text.trim();
    final typedRefreshToken = _aliyunRefreshToken.text.trim();
    final typedAccessToken = _aliyunAccessToken.text.trim();
    final accessTokenChanged =
        typedAccessToken != (stored?.aliyunDriveAccessToken?.trim() ?? '');
    return BabyCloudSource(
      id: _sourceId,
      name: _name.text.trim().isEmpty ? _defaultName : _name.text.trim(),
      type: _type,
      status: 'notInitialized',
      rootPath: rootText.isEmpty ? 'starbank_baby_cloud' : rootText,
      webDavUrl: _type == 'webdav' ? _externalUrl.text.trim() : null,
      webDavLanUrl: _type == 'webdav' ? _lanUrl.text.trim() : null,
      webDavUsername: _type == 'webdav' ? _user.text.trim() : null,
      webDavPassword: _type == 'webdav' ? _password.text : null,
      webDavEndpointMode: _type == 'webdav' ? _webDavEndpointMode : 'auto',
      aliyunDriveClientId:
          _type == 'aliyunDrive' ? _aliyunClientId.text.trim() : null,
      aliyunDriveClientSecret:
          _type == 'aliyunDrive' ? _aliyunClientSecret.text.trim() : null,
      aliyunDriveRedirectUri:
          _type == 'aliyunDrive' ? _aliyunRedirectUri.text.trim() : null,
      aliyunDriveScope:
          _type == 'aliyunDrive' ? _aliyunScope.text.trim() : null,
      aliyunDriveAuthUrl:
          _type == 'aliyunDrive' ? _aliyunAuthUrl.text.trim() : null,
      aliyunDriveTokenUrl:
          _type == 'aliyunDrive' ? _aliyunTokenUrl.text.trim() : null,
      aliyunDriveRefreshToken: _type == 'aliyunDrive'
          ? typedRefreshToken.isNotEmpty
              ? typedRefreshToken
              : stored?.aliyunDriveRefreshToken
          : null,
      aliyunDriveAccessToken: _type == 'aliyunDrive'
          ? typedAccessToken.isNotEmpty
              ? typedAccessToken
              : null
          : null,
      aliyunDriveTokenExpiresAt: _type == 'aliyunDrive' && !accessTokenChanged
          ? stored?.aliyunDriveTokenExpiresAt
          : null,
      aliyunDriveDriveId:
          _type == 'aliyunDrive' ? stored?.aliyunDriveDriveId : null,
      aliyunDriveUserId:
          _type == 'aliyunDrive' ? stored?.aliyunDriveUserId : null,
      aliyunDriveNickName:
          _type == 'aliyunDrive' ? stored?.aliyunDriveNickName : null,
      createdAt: source?.createdAt ?? stored?.createdAt,
    );
  }

  BabyCloudSource? _storedSource() {
    return _cloud.sources.firstWhereOrNull((item) => item.id == _sourceId);
  }

  String get _defaultName => _type == 'webdav' ? '亲宝宝 WebDAV' : '阿里云盘';

  bool _hasRequiredSourceInput(BabyCloudSource source) {
    if (source.isAliyunDrive) {
      return source.aliyunDriveClientId?.trim().isNotEmpty == true ||
          source.aliyunDriveAccessToken?.trim().isNotEmpty == true ||
          source.aliyunDriveRefreshToken?.trim().isNotEmpty == true;
    }
    final mode = _normalizeWebDavEndpointMode(source.webDavEndpointMode);
    if (mode == 'lan') {
      return source.webDavLanUrl?.trim().isNotEmpty == true;
    }
    if (mode == 'external') {
      return source.webDavUrl?.trim().isNotEmpty == true;
    }
    return (source.webDavUrl?.trim().isNotEmpty ?? false) ||
        (source.webDavLanUrl?.trim().isNotEmpty ?? false);
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.selected,
    required this.checking,
    required this.onModeChanged,
    required this.onSelect,
    required this.onCheck,
    required this.onEdit,
    required this.onDirectory,
  });

  final BabyCloudSource source;
  final bool selected;
  final bool checking;
  final ValueChanged<String>? onModeChanged;
  final VoidCallback onSelect;
  final VoidCallback onCheck;
  final VoidCallback onEdit;
  final VoidCallback onDirectory;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12.r),
      elevation: selected ? 2 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onSelect,
        child: Padding(
          padding: EdgeInsets.all(14.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42.w,
                    height: 42.w,
                    decoration: BoxDecoration(
                      color: _typeColor(source).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(
                      _typeIcon(source),
                      color: _typeColor(source),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Wrap(
                          spacing: 6.w,
                          runSpacing: 6.h,
                          children: [
                            _StatusChip(
                              label: _typeLabel(source),
                              color: _typeColor(source),
                            ),
                            _StatusChip(
                              label: _statusLabel(source.status),
                              color: _statusColor(source.status),
                            ),
                            if (source.isWebDav)
                              _StatusChip(
                                label: _endpointModeLabel(
                                  source.webDavEndpointMode,
                                ),
                                color: Colors.indigo,
                              ),
                            if (source.isWebDav &&
                                source.activeWebDavEndpoint != 'none')
                              _StatusChip(
                                label:
                                    '当前${_endpointLabel(source.activeWebDavEndpoint)}',
                                color: Colors.blueGrey,
                              ),
                            if (selected)
                              const _StatusChip(
                                label: '已选择',
                                color: Colors.green,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (checking)
                    SizedBox(
                      width: 22.w,
                      height: 22.w,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    PopupMenuButton<String>(
                      tooltip: '数据源操作',
                      onSelected: (value) {
                        switch (value) {
                          case 'check':
                            onCheck();
                            break;
                          case 'edit':
                            onEdit();
                            break;
                          case 'directory':
                            onDirectory();
                            break;
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'check',
                          child: Text('检查可用性'),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('编辑数据源'),
                        ),
                        const PopupMenuItem(
                          value: 'directory',
                          child: Text('选择云端目录'),
                        ),
                      ],
                    ),
                ],
              ),
              if (source.isWebDav) ...[
                SizedBox(height: 12.h),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'auto',
                        label: Text('自动'),
                        icon: Icon(Icons.auto_awesome_outlined),
                      ),
                      ButtonSegment<String>(
                        value: 'lan',
                        label: Text('内网'),
                        icon: Icon(Icons.wifi),
                      ),
                      ButtonSegment<String>(
                        value: 'external',
                        label: Text('外网'),
                        icon: Icon(Icons.public),
                      ),
                    ],
                    selected: {
                      _normalizeWebDavEndpointMode(source.webDavEndpointMode),
                    },
                    onSelectionChanged: checking || onModeChanged == null
                        ? null
                        : (selection) {
                            if (selection.isEmpty) return;
                            onModeChanged!(selection.first);
                          },
                  ),
                ),
              ],
              SizedBox(height: 12.h),
              if (source.isWebDav) ...[
                _DetailLine(
                  label: '模式',
                  value: _endpointModeLabel(source.webDavEndpointMode),
                ),
                SizedBox(height: 4.h),
                _DetailLine(label: '外网', value: source.webDavUrl),
                SizedBox(height: 4.h),
                _DetailLine(label: '内网', value: source.webDavLanUrl),
                SizedBox(height: 4.h),
              ] else ...[
                _DetailLine(label: '接口', value: '阿里云盘官方开放接口'),
                SizedBox(height: 4.h),
                _DetailLine(
                  label: '授权',
                  value: source.aliyunDriveRefreshToken?.trim().isNotEmpty ==
                          true
                      ? '已保存 refresh token'
                      : source.aliyunDriveAccessToken?.trim().isNotEmpty == true
                          ? '已保存 access token'
                          : '待授权或填写令牌',
                ),
                SizedBox(height: 4.h),
                if (source.aliyunDriveNickName?.trim().isNotEmpty == true) ...[
                  _DetailLine(label: '账号', value: source.aliyunDriveNickName),
                  SizedBox(height: 4.h),
                ],
                if (source.aliyunDriveDriveId?.trim().isNotEmpty == true) ...[
                  _DetailLine(label: '盘ID', value: source.aliyunDriveDriveId),
                  SizedBox(height: 4.h),
                ],
              ],
              _DetailLine(label: '根目录', value: source.rootPath),
              if (source.lastCheckMessage?.isNotEmpty == true) ...[
                SizedBox(height: 8.h),
                _CheckMessagePanel(source: source),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'normal':
        return '可用';
      case 'invalid':
        return '不可用';
      case 'syncing':
        return '同步中';
      case 'readOnly':
        return '只读';
      default:
        return '未检测';
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'normal':
        return Colors.green;
      case 'invalid':
        return Colors.red;
      case 'syncing':
        return Colors.blue;
      case 'readOnly':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  static String _endpointLabel(String endpoint) {
    if (endpoint == 'lan') return '内网';
    if (endpoint == 'external') return '外网';
    return '未选择';
  }

  static String _typeLabel(BabyCloudSource source) {
    if (source.isAliyunDrive) return '阿里云盘';
    return 'WebDAV';
  }

  static IconData _typeIcon(BabyCloudSource source) {
    if (source.isAliyunDrive) return Icons.cloud_outlined;
    return Icons.cloud_queue;
  }

  static Color _typeColor(BabyCloudSource source) {
    if (source.isAliyunDrive) return Colors.blue.shade600;
    return Colors.pink.shade400;
  }
}

class _CheckMessagePanel extends StatelessWidget {
  const _CheckMessagePanel({required this.source});

  final BabyCloudSource source;

  @override
  Widget build(BuildContext context) {
    final message = source.lastCheckMessage?.trim() ?? '';
    final isOk = source.status == 'normal';
    final color = isOk ? Colors.green.shade700 : Colors.red.shade700;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(left: 10.w, right: 4.w, top: 8.h, bottom: 8.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.sp,
                color: color,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 4.w),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: BoxConstraints.tight(Size(32.w, 32.w)),
            padding: EdgeInsets.zero,
            tooltip: isOk ? '查看完整检查信息' : '查看完整错误信息',
            icon: Icon(
              Icons.info_outline,
              size: 18.sp,
              color: color,
            ),
            onPressed: () => _showFullMessage(context, message, isOk),
          ),
        ],
      ),
    );
  }

  void _showFullMessage(BuildContext context, String message, bool isOk) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isOk ? '检查详情' : '错误详情'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.55,
            maxWidth: MediaQuery.of(dialogContext).size.width * 0.82,
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              message,
              style: TextStyle(fontSize: 13.sp, height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              ToastUtils.showSuccess('已复制检查信息');
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final text = value?.trim().isNotEmpty == true ? value!.trim() : '未填写';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42.w,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.sp,
              color: text == '未填写' ? Colors.grey : Colors.black87,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _WebDavDirectoryPicker extends StatefulWidget {
  const _WebDavDirectoryPicker({
    required this.source,
    required this.initialPath,
    required this.persistCheck,
  });

  final BabyCloudSource source;
  final String initialPath;
  final bool persistCheck;

  @override
  State<_WebDavDirectoryPicker> createState() => _WebDavDirectoryPickerState();
}

class _WebDavDirectoryPickerState extends State<_WebDavDirectoryPicker> {
  final _cloud = Get.find<BabyCloudService>();

  late String _path;
  List<Map<String, dynamic>> _dirs = const [];
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = _normalizePath(widget.initialPath);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.source.isWebDav ? '选择 WebDAV 目录' : '选择阿里云盘目录',
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                _path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.sp, color: Colors.black87),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              _PickerActionButton(
                icon: Icons.arrow_upward,
                label: '上级',
                onPressed: _path == '/'
                    ? () => ToastUtils.showInfo('已经在云端根目录')
                    : _goParent,
              ),
              SizedBox(width: 8.w),
              _PickerActionButton(
                icon: Icons.refresh,
                label: '刷新',
                onPressed: _load,
              ),
              SizedBox(width: 8.w),
              _PickerActionButton(
                icon: Icons.create_new_folder_outlined,
                label: '新建',
                onPressed: _working ? _busyTip : _createDirectory,
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _working
                    ? _busyTip
                    : () => Navigator.of(context).pop(_path),
                icon: const Icon(Icons.check),
                label: const Text('选择此目录'),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Expanded(
            child: _buildDirectoryBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectoryBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 42.sp,
                color: Colors.red.shade200,
              ),
              SizedBox(height: 10.h),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.sp, height: 1.35),
              ),
              SizedBox(height: 12.h),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重新读取'),
              ),
            ],
          ),
        ),
      );
    }
    if (_dirs.isEmpty) {
      return Center(
        child: Text(
          '当前目录没有子目录',
          style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600),
        ),
      );
    }
    return ListView.separated(
      itemCount: _dirs.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
      itemBuilder: (_, index) {
        final dir = _dirs[index];
        final path = dir['path']?.toString() ?? '/';
        final name = dir['name']?.toString() ?? path;
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(name),
          subtitle: Text(
            path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () {
            setState(() => _path = path);
            _load();
          },
          trailing: IconButton(
            tooltip: '重命名目录',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _working ? _busyTip : () => _renameDirectory(path, name),
          ),
        );
      },
    );
  }

  Future<void> _load() async {
    if (_working) {
      _busyTip();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dirs = await _cloud.listRemoteDirectories(
        widget.source,
        _path,
        persistCheck: widget.persistCheck,
      );
      if (!mounted) return;
      setState(() => _dirs = dirs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createDirectory() async {
    final name = await _askName(title: '新建目录');
    if (name == null) return;
    setState(() => _working = true);
    try {
      final newPath = await _cloud.createRemoteDirectory(
        widget.source,
        _path,
        name,
        persistCheck: widget.persistCheck,
      );
      ToastUtils.showSuccess('目录已创建');
      if (!mounted) return;
      setState(() => _path = newPath);
      await _load();
    } catch (e) {
      ToastUtils.showError('新建目录失败: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _renameDirectory(String path, String currentName) async {
    final name = await _askName(title: '修改目录名', initialValue: currentName);
    if (name == null) return;
    setState(() => _working = true);
    try {
      await _cloud.renameRemoteDirectory(
        widget.source,
        path,
        name,
        persistCheck: widget.persistCheck,
      );
      ToastUtils.showSuccess('目录已重命名');
      await _load();
    } catch (e) {
      ToastUtils.showError('重命名失败: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _askName({
    required String title,
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);
    return Get.dialog<String>(
      AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '目录名',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) {
                ToastUtils.showWarning('目录名不能为空');
                return;
              }
              Get.back(result: value);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _goParent() {
    if (_path == '/') {
      ToastUtils.showInfo('已经在云端根目录');
      return;
    }
    final index = _path.lastIndexOf('/');
    setState(() => _path = index <= 0 ? '/' : _path.substring(0, index));
    _load();
  }

  void _busyTip() {
    ToastUtils.showInfo('正在处理云端目录，请稍等');
  }

  String _normalizePath(String path) {
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
}

class _PickerActionButton extends StatelessWidget {
  const _PickerActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18.sp),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      ),
    );
  }
}

class _RemoteBabyDirPage extends StatefulWidget {
  const _RemoteBabyDirPage({
    required this.dirs,
    required this.localBabyIds,
  });

  final List<Map<String, dynamic>> dirs;
  final Set<String> localBabyIds;

  @override
  State<_RemoteBabyDirPage> createState() => _RemoteBabyDirPageState();
}

class _RemoteBabyDirPageState extends State<_RemoteBabyDirPage> {
  late final List<Map<String, dynamic>> _dirs = List.of(widget.dirs);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('云端宝宝目录')),
      body: _dirs.isEmpty
          ? Center(
              child: Text(
                '没有发现云端宝宝目录',
                style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600),
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(16.w),
              itemCount: _dirs.length,
              itemBuilder: (_, index) {
                final dir = _dirs[index];
                final remoteLocalIds =
                    ((dir['localBabyIds'] as List?) ?? const <dynamic>[])
                        .map((e) => e.toString())
                        .toSet();
                if (remoteLocalIds.isEmpty &&
                    dir['babyId']?.toString().isNotEmpty == true) {
                  remoteLocalIds.add(dir['babyId'].toString());
                }
                final linked = remoteLocalIds
                    .any((id) => widget.localBabyIds.contains(id));
                final cloudBabyId = dir['cloudBabyId']?.toString() ?? '';
                return Card(
                  child: ListTile(
                    title: Text(dir['name']?.toString() ?? ''),
                    subtitle: Text(
                      '${linked ? '已关联当前宝宝资料' : 'manifest 中记录的云端宝宝，当前本地未关联'}'
                      '${cloudBabyId.isEmpty ? '' : '\n云端 ID：$cloudBabyId'}'
                      '\n${dir['path']}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}
