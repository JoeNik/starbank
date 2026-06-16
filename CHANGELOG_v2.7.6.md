# v2.7.6 更新日志

## 🔐 修复家长密码异步初始化问题

### 问题描述
调试过程中发现密码错误的情况，经分析是异步初始化竞态条件导致。

### 问题根源
- `AppModeController` 的 Hive box 异步打开，但没有等待完成
- 在初始化未完成时访问 `passwordHash` 可能返回 `null` 或崩溃
- WebDAV 备份/恢复时可能在初始化前执行，导致备份空密码或恢复失败

### 修复内容

#### 1. 添加初始化检查
```dart
String? get passwordHash {
  if (!_isInitialized) return null;  // 防止访问未初始化的 box
  return _settingsBox.get(_passwordKey);
}
```

#### 2. 添加等待初始化方法
```dart
Future<void> ensureInitialized() async {
  if (_isInitialized) return;
  await _initSettings();
}
```

#### 3. WebDAV 备份前等待初始化
```dart
final modeController = Get.find<AppModeController>();
await modeController.ensureInitialized(); // 确保初始化完成
if (modeController.hasPassword) {
  backupData['passwordHash'] = modeController.passwordHash;
}
```

#### 4. WebDAV 恢复前等待初始化
```dart
final modeController = Get.find<AppModeController>();
await modeController.ensureInitialized(); // 确保初始化完成
await modeController.restorePasswordHash(backupData['passwordHash']);
```

### 修复效果

**修复前**：
- 启动后立即备份可能备份空密码
- 恢复时可能覆盖正确密码
- 导致用户密码丢失

**修复后**：
- 备份前确保初始化完成
- 恢复前确保初始化完成
- 密码正常保存和恢复

### 其他可能导致密码清空的场景

1. ✅ **WebDAV 恢复备份**（设计行为）
   - 恢复备份时会恢复备份时的密码
   - 这是正常行为

2. ✅ **应用数据被清除**（用户操作）
   - 系统设置清除应用数据
   - 卸载重装应用
   - 可以通过 WebDAV 恢复找回密码

3. ❌ **没有主动清除密码的方法**
   - 代码中没有 `clearPassword()` 功能
   - 这是安全的设计

## 📝 技术改进

- 修复异步初始化竞态条件
- 添加初始化完成检查
- 增强云备份数据完整性

## 📄 文档更新

- 新增《家长密码问题分析与修复.md》

---

**版本号**：v2.7.6
**修复日期**：2026-06-17
**修复文件**：2 个核心文件
**代码变更**：+27 行 / -4 行
