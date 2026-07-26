import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../services/family_sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/toast_utils.dart';

/// 家庭同步设置页：配置自部署的 Cloudflare 服务端端点，
/// 启用后强制在本页登录/注册家庭号；不启用则保持纯本地模式。
class FamilySyncPage extends StatefulWidget {
  const FamilySyncPage({super.key});

  @override
  State<FamilySyncPage> createState() => _FamilySyncPageState();
}

class _FamilySyncPageState extends State<FamilySyncPage> {
  final _sync = Get.find<FamilySyncService>();
  final _endpointController = TextEditingController();
  bool _busy = false;
  Future<List<Map<String, dynamic>>>? _membersFuture;

  Future<List<Map<String, dynamic>>> _membersOnce() {
    return _membersFuture ??= _sync.fetchMembers();
  }

  void _reloadMembers() {
    setState(() => _membersFuture = _sync.fetchMembers());
  }

  @override
  void initState() {
    super.initState();
    _endpointController.text = _sync.endpoint.value;
  }

  @override
  void dispose() {
    _endpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('家庭同步')),
      body: Obx(() {
        final loggedIn = _sync.enabled.value && _sync.isLoggedIn;
        return ListView(
          padding: EdgeInsets.all(16.w),
          children: loggedIn ? _buildConnectedView() : _buildSetupView(),
        );
      }),
    );
  }

  // ------------------------------------------------------------------
  // 未启用：介绍 + 端点配置 + 登录/注册
  // ------------------------------------------------------------------

  List<Widget> _buildSetupView() {
    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.family_restroom,
                    color: AppTheme.primaryDark, size: 22.sp),
                SizedBox(width: 8.w),
                Text('多设备家庭同步',
                    style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w900)),
              ],
            ),
            SizedBox(height: 8.h),
            Text(
              '通过你自己部署的 Cloudflare Worker 服务端，让两位家长的手机实时同步'
              '星星、日志、成长记录与 AI 配置等数据。\n\n'
              '· 不配置则完全本地使用，无任何网络行为\n'
              '· 首次注册自动创建家庭并成为主号\n'
              '· 主号可为另一半创建子号',
              style: TextStyle(
                  fontSize: 13.sp, color: AppTheme.textSub, height: 1.6),
            ),
          ],
        ),
      ),
      SizedBox(height: 12.h),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('服务端端点',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w800)),
            SizedBox(height: 8.h),
            TextField(
              controller: _endpointController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://sync.example.com',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                isDense: true,
              ),
            ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _connectEndpoint,
                icon: _busy
                    ? SizedBox.square(
                        dimension: 16.w,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: const Text('连接服务端'),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _connectEndpoint() async {
    final endpoint = _endpointController.text.trim();
    if (!endpoint.startsWith('https://') && !endpoint.startsWith('http://')) {
      ToastUtils.showWarning('端点需以 https:// 开头');
      return;
    }
    setState(() => _busy = true);
    try {
      await _sync.saveEndpoint(endpoint);
      // 先做连通性检查，失败给出具体原因，成功再进入强制登录/注册
      await _sync.testEndpoint();
      // 全屏登录页：表单从顶部排布，键盘弹起不会压缩输入框
      final result =
          await Get.to<FirstLoginResult>(() => const _FamilySyncAuthPage());
      if (result == FirstLoginResult.needMergeChoice) {
        _showMergeChoiceDialog();
      }
    } on FamilySyncException catch (e) {
      ToastUtils.showError(e.message);
    } catch (e) {
      ToastUtils.showError('连接失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMergeChoiceDialog() {
    Get.dialog(
      barrierDismissible: false,
      AlertDialog(
        title: const Text('云端已有家庭数据'),
        content: const Text(
          '这台手机上也有本地数据，请选择处理方式：\n\n'
          '【以云端为准】本地核心数据将被云端替换（替换前会自动保存一份本地快照文件，可找回）。'
          '推荐第二台设备使用。\n\n'
          '【合并上传】本地与云端数据都保留。注意：同一个孩子若在两台设备上分别建过档案，'
          '会出现两个宝宝，需要手动删除多余的。',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Get.back();
              await _runBusy(() async {
                await _sync.mergeUpload();
                ToastUtils.showSuccess('已合并上传本地数据');
              });
            },
            child: const Text('合并上传'),
          ),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              await _runBusy(() async {
                final backupPath = await _sync.adoptCloud();
                ToastUtils.showSuccess('已切换为云端数据\n本地快照: $backupPath');
              });
            },
            child: const Text('以云端为准（推荐）'),
          ),
        ],
      ),
    );
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on FamilySyncException catch (e) {
      ToastUtils.showError(e.message);
    } catch (e) {
      ToastUtils.showError('操作失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------
  // 已启用：状态 + 成员管理
  // ------------------------------------------------------------------

  List<Widget> _buildConnectedView() {
    final timeFormat = DateFormat('MM-dd HH:mm:ss');
    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.home_rounded,
                    color: AppTheme.primaryDark, size: 22.sp),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    _sync.familyName.value.isEmpty
                        ? '我的家庭'
                        : _sync.familyName.value,
                    style:
                        TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w900),
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: _sync.isOwner
                        ? const Color(0xFFFFF4D0)
                        : const Color(0xFFE7F4FE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _sync.isOwner ? '主号' : '子号',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w800,
                      color: _sync.isOwner
                          ? const Color(0xFF8A5C00)
                          : const Color(0xFF255E93),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            Text('账号：${_sync.username.value}',
                style: TextStyle(fontSize: 13.sp, color: AppTheme.textSub)),
            Text('端点：${_sync.endpoint.value}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.sp, color: AppTheme.textSub)),
            SizedBox(height: 6.h),
            Obx(() {
              if (_sync.syncing.value) {
                return Padding(
                  padding: EdgeInsets.only(top: 4.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 5.h,
                          backgroundColor: const Color(0xFFFFE4E6),
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text('正在同步数据…',
                          style: TextStyle(
                              fontSize: 12.sp, color: AppTheme.textSub)),
                    ],
                  ),
                );
              }
              final error = _sync.lastError.value;
              if (error.isNotEmpty) {
                return Text('上次同步出错：$error',
                    style: TextStyle(fontSize: 13.sp, color: Colors.red));
              }
              final at = _sync.lastSyncAt.value;
              return Text(
                at == null ? '尚未同步' : '上次同步：${timeFormat.format(at)}',
                style: TextStyle(fontSize: 13.sp, color: Colors.green.shade700),
              );
            }),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _sync.syncing.value
                        ? null
                        : () => _sync.syncNow(manual: true),
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('立即同步'),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _confirmLogout,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('退出并停用'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      SizedBox(height: 12.h),
      if (_sync.isOwner) _buildMembersCard(),
      SizedBox(height: 12.h),
      _card(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.password),
          title: const Text('修改我的密码'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
          onTap: _showChangePasswordDialog,
        ),
      ),
    ];
  }

  Widget _buildMembersCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('家庭成员',
                  style:
                      TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w900)),
              const Spacer(),
              TextButton.icon(
                onPressed: _showCreateMemberDialog,
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('添加子号'),
              ),
            ],
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _membersOnce(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(
                  padding: EdgeInsets.all(12.h),
                  child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: EdgeInsets.all(8.h),
                  child: Text('加载成员失败：${snapshot.error}',
                      style: TextStyle(fontSize: 12.sp, color: Colors.red)),
                );
              }
              final members = snapshot.data ?? const [];
              return Column(
                children: [
                  for (final member in members)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        member['role'] == 'owner'
                            ? Icons.star_rounded
                            : Icons.person_outline,
                        color: member['role'] == 'owner'
                            ? Colors.amber
                            : AppTheme.textSub,
                      ),
                      title: Text(member['username']?.toString() ?? ''),
                      subtitle: Text(member['role'] == 'owner' ? '主号' : '子号'),
                      trailing: member['role'] == 'owner'
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: '重置密码',
                                  icon: const Icon(Icons.lock_reset, size: 20),
                                  onPressed: () => _showResetMemberDialog(
                                    member['id'].toString(),
                                    member['username'].toString(),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '移除成员',
                                  icon: const Icon(Icons.person_remove_alt_1,
                                      size: 20, color: Colors.red),
                                  onPressed: () => _confirmRemoveMember(
                                    member['id'].toString(),
                                    member['username'].toString(),
                                  ),
                                ),
                              ],
                            ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _showCreateMemberDialog() {
    final userController = TextEditingController();
    final passwordController = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text('添加子号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userController,
              decoration: const InputDecoration(labelText: '子号用户名'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: '初始密码（至少 6 位）'),
            ),
            SizedBox(height: 8.h),
            const Text(
              '创建后把用户名和初始密码告诉另一半，在 TA 的手机上登录即可加入家庭。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              try {
                await _sync.createMember(
                  userController.text.trim(),
                  passwordController.text,
                );
                Get.back();
                ToastUtils.showSuccess('子号已创建');
                _reloadMembers();
              } on FamilySyncException catch (e) {
                ToastUtils.showError(e.message);
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showResetMemberDialog(String userId, String username) {
    final passwordController = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: Text('重置 $username 的密码'),
        content: TextField(
          controller: passwordController,
          decoration: const InputDecoration(labelText: '新密码（至少 6 位）'),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              try {
                await _sync.resetMemberPassword(
                    userId, passwordController.text);
                Get.back();
                ToastUtils.showSuccess('密码已重置');
              } on FamilySyncException catch (e) {
                ToastUtils.showError(e.message);
              }
            },
            child: const Text('重置'),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveMember(String userId, String username) {
    Get.dialog(
      AlertDialog(
        title: const Text('移除成员'),
        content: Text('确定把 $username 移出家庭吗？TA 将无法再同步，但云端数据保留。'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await _sync.removeMember(userId);
                Get.back();
                ToastUtils.showSuccess('已移除');
                _reloadMembers();
              } on FamilySyncException catch (e) {
                ToastUtils.showError(e.message);
              }
            },
            child: const Text('移除'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final oldController = TextEditingController();
    final newController = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '原密码'),
            ),
            TextField(
              controller: newController,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码（至少 6 位）'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              try {
                await _sync.changePassword(
                    oldController.text, newController.text);
                Get.back();
                ToastUtils.showSuccess('密码已修改');
              } on FamilySyncException catch (e) {
                ToastUtils.showError(e.message);
              }
            },
            child: const Text('修改'),
          ),
        ],
      ),
    );
  }

  void _confirmLogout() {
    Get.dialog(
      AlertDialog(
        title: const Text('退出并停用同步'),
        content: const Text('退出后本机不再同步（本地数据保留，云端数据保留）。确定吗？'),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              await _runBusy(() => _sync.logoutAndDisable());
              ToastUtils.showSuccess('已停用家庭同步');
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFFEDE5D8)),
      ),
      child: child,
    );
  }
}

/// 全屏登录/注册页：表单从顶部排布，键盘弹起只收起底部空间，
/// 输入框不会被压缩或遮挡。
class _FamilySyncAuthPage extends StatefulWidget {
  const _FamilySyncAuthPage();

  @override
  State<_FamilySyncAuthPage> createState() => _FamilySyncAuthPageState();
}

class _FamilySyncAuthPageState extends State<_FamilySyncAuthPage> {
  final _sync = Get.find<FamilySyncService>();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _familyController = TextEditingController();
  bool _isRegister = false;
  bool _working = false;
  bool _obscure = true;

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    _familyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF6F2),
      appBar: AppBar(
        title: Text(_isRegister ? '注册家庭号' : '登录家庭号'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 32.h),
        children: [
          Center(
            child: Container(
              width: 84.w,
              height: 84.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9A9E), Color(0xFFFFC371)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF9A9E).withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text('👨‍👩‍👧', style: TextStyle(fontSize: 38.sp)),
            ),
          ),
          SizedBox(height: 14.h),
          Text(
            _isRegister ? '创建你的家庭' : '欢迎回来',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.w900,
              color: AppTheme.textMain,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            _isRegister ? '首次注册自动创建家庭，你将成为主号' : '启用家庭同步需要登录家庭号',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.sp, color: AppTheme.textSub),
          ),
          SizedBox(height: 22.h),
          Container(
            padding: EdgeInsets.all(18.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: const Color(0xFFFFE4E6), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4E342E).withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _userController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '用户名',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                ),
                SizedBox(height: 14.h),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  textInputAction:
                      _isRegister ? TextInputAction.next : TextInputAction.done,
                  onSubmitted: (_) {
                    if (!_isRegister) _submit();
                  },
                  decoration: InputDecoration(
                    labelText: '密码（至少 6 位）',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                ),
                if (_isRegister) ...[
                  SizedBox(height: 14.h),
                  TextField(
                    controller: _familyController,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: '家庭名称（可选）',
                      prefixIcon: const Icon(Icons.home_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 20.h),
          SizedBox(
            height: 48.h,
            child: ElevatedButton(
              onPressed: _working ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.r),
                ),
              ),
              child: _working
                  ? SizedBox.square(
                      dimension: 20.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isRegister ? '注册并启用同步' : '登录并启用同步',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
          SizedBox(height: 8.h),
          TextButton(
            onPressed: _working
                ? null
                : () => setState(() => _isRegister = !_isRegister),
            child: Text(
              _isRegister ? '已有家庭号？去登录' : '还没有家庭号？注册一个',
              style: TextStyle(fontSize: 14.sp),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final username = _userController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.length < 6) {
      ToastUtils.showWarning('请输入用户名和至少 6 位密码');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _working = true);
    try {
      if (_isRegister) {
        await _sync.register(
          user: username,
          password: password,
          familyDisplayName: _familyController.text.trim(),
        );
        ToastUtils.showSuccess('注册成功，数据正在后台同步');
        Get.back(result: FirstLoginResult.done);
      } else {
        final result = await _sync.login(user: username, password: password);
        if (result == FirstLoginResult.done) {
          ToastUtils.showSuccess('登录成功，数据正在后台同步');
        }
        Get.back(result: result);
      }
    } on FamilySyncException catch (e) {
      ToastUtils.showError(e.message);
    } catch (e) {
      ToastUtils.showError('操作失败: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}
