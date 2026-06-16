# 亲宝宝云相册维护说明

下次修复或继续开发「亲宝宝」「云相册」「亲宝宝 WebDAV 数据源」「回收站/永久删除」「多端同步」相关内容前，必须先读这份文档。

这份文档记录本会话里讨论过的问题、最终实现方案、数据安全约束和后续改动注意事项。当前亲宝宝云相册仍处于开发期，远端旧测试结构不再迁移、不再兼容；代码只维护下面定义的最新版云端结构。

## 本会话问题清单

这次围绕亲宝宝功能，陆续讨论和修复过以下问题：

- 「记录」改为「亲宝宝」，云相册作为主页面，便便记录、生长记录、宝宝大事记放到后续 tab。
- 云相册页面参考亲宝宝截图设计，包含时间轴、可折叠头图/头像/tab、数据源控件、上传入口、搜索和筛选。
- 自定义 Android 媒体选择器按时间倒序展示，减少大量照片时的卡顿；已上传媒体按 SHA-256 识别后置灰。
- 没有配置亲宝宝云相册数据源时，上传必须提示用户，不能创建假任务。
- 上传后应关闭媒体选择器/编辑页，任务进入后台队列执行，并展示进度。
- WebDAV 需要支持 HTTP 和 HTTPS，支持内网/外网地址；在局域网时优先检测内网地址，内网不可用再尝试外网。
- WebDAV 连接失败时，要展示完整错误信息；根目录不存在时要自动创建。
- WebDAV 目录选择需要支持新增目录、重命名目录。
- 阿里云盘数据源支持两种登录方式：官方开放接口 OAuth 授权码模式，以及类似 OpenList/AList 的令牌登录。OAuth 浏览器登录后应能通过 `starbank://aliyundrive/oauth` 回跳 App，也支持粘贴回调链接或 code 手动完成授权；令牌登录允许直接填写 Access Token，或填写 Refresh Token 后按开放接口刷新。
- WebDAV 和阿里云盘只能替换底层远端文件客户端，上层 `library_manifest.json`、`album_index.json`、队列、软删除/永久删除规则必须共用同一套逻辑。
- 相册和视频需要分开目录存储，并按月份归档：`album/photos/2026/06`、`album/videos/2026/06`、`album/audios/2026/06`。
- 上传成功后相册不能空白，图片、视频、录音应能正常展示/播放。
- 时间轴上的视频/录音标识要明显，不显示文件名水印。
- 上传动态前进入编辑页，可填写文字说明、标签、位置、记录时间。
- 右上角上传菜单支持照片/视频、拍摄、录音、录音文件、日记。
- 搜索支持文字、标签、日期，并可筛选照片、视频、录音、纯文字。
- 日历控件中文化，头像背景支持本地更换。
- 「所在位置」弹框曾触发 framework assertion，需要避免跨 context/route 的错误用法。
- 启动曾出现 `UserController not found`，已通过启动绑定修复；以后不要破坏 `main.dart` 的核心 DI 顺序。
- 成长记录、大事记与便便记录使用系统级备份/恢复；只有亲宝宝云相册使用独立 WebDAV/阿里云盘数据源。
- 大事记应关联云相册动态标签并同步展现。
- 大事记必须支持手动添加；保存时要自动匹配同名云相册标签，并关联带这些标签的云相册媒体。
- 多端使用时，新设备配置 WebDAV 后，必须能同步云端已有宝宝数据，不能只显示本地新索引。
- 切换数据源时，不能清空本地或覆盖远端；需要让用户自行确认是否同步远端数据。
- 默认永不物理删除云端文件；普通删除只进入回收站并写删除标记。
- 回收站删除的内容需要区分「整条动态」和「单文件」。
- 永久删除云端原文件必须是明确入口、家长控制、密码确认、可预览路径的流程。

## 最终实现概览

### 入口和页面

- `lib/pages/record_page.dart`
  - 亲宝宝模块主入口。
  - 云相册是第一个 tab。
  - 便便、生长、大事记收拢在后续 tab。
  - 时间轴按日期分组，并按动态分组展示媒体、文字、标签、位置和时间。
  - 时间轴动态的 `...` 菜单支持编辑和删除动态。
  - 搜索支持文字、标签、日期、照片、视频、录音、纯文字。

- `lib/pages/milestone_page.dart`
  - 大事记支持手动添加、截图 OCR 导入、编辑和回收站。
  - 手动添加/编辑时可输入标题、分类、描述和标签，可选择云相册媒体。
  - 保存时会把手动标签、已关联媒体标签、标题/分类/描述中命中的云相册标签合并，并自动关联带同名标签的云相册媒体。

- `lib/pages/kin/baby_cloud_entry_edit_page.dart`
  - 新建动态时填写文字说明、标签、位置和记录时间。
  - 支持照片/视频、拍摄文件、录音、录音文件、日记。
  - 已支持编辑已有动态的元数据：文字、标签、位置、时间；保存时先写本地并立即返回，云端 index 发布进入后台任务。
  - 注意：服务层已经为媒体替换预留删除原因和替换指向字段，但「更换媒体文件」的完整 UI 流程还没有最终完成。后续做这个功能时，要按本文的删除标记规则实现。

- `lib/pages/kin/baby_cloud_recycle_bin_page.dart`
  - 回收站只负责查看和恢复。
  - 分为整条动态和单文件。
  - 不再在普通回收站里直接物理删除云端文件。

- `lib/pages/kin/baby_cloud_permanent_delete_page.dart`
  - 唯一明确的「永久删除云端原文件」页面。
  - 只列出已删除但未永久清理的整条动态/单文件。
  - 永久删除前需要家长模式和密码确认。
  - 确认后只提交后台任务并返回上一级，不阻塞前端等待 WebDAV 删除。
  - 整条动态永久删除任务会删除该动态关联的所有云端媒体和缩略图。
  - 单文件永久删除任务只删除该文件和对应缩略图。

- `lib/pages/kin/baby_cloud_source_page.dart`
  - 亲宝宝独立数据源配置页。
  - 支持 WebDAV 内网/外网地址、HTTP/HTTPS、手动检测、目录选择、新建目录、重命名目录。
  - 支持阿里云盘官方开放接口数据源。首屏只保留 OAuth 必填要素（Client ID、Redirect URI）和令牌登录（Access Token、Refresh Token）；Client Secret、scope、OAuth 端点放在高级设置里。
  - 切换数据源后会提示是否立即同步远端。
  - 旧的「物理删除云端宝宝目录」入口已移除，避免误删整个目录树。

### 数据模型

- `lib/models/baby_cloud_entry.dart`
  - 独立动态模型，是时间轴和删除/恢复的主模型。
  - 关键字段：
    - `libraryId`：云端库身份。
    - `cloudBabyId`：云端宝宝身份。
    - `entryType`：`media` / `diary` / `mixed` / `audio`。
    - `mediaIds`：动态关联的媒体 ID。
    - `deletedAt` / `deleteReason`：软删除标记。
    - `purgedAt`：已执行永久云端删除的标记。

- `lib/models/baby_cloud_media.dart`
  - 媒体文件模型，保存照片、视频、录音和日记占位项。
  - 新增字段：
    - `libraryId`
    - `cloudBabyId`
    - `deleteReason`
    - `replacedByMediaId`
    - `purgedAt`
  - 媒体是文件资源，不再是动态本身。以后不要只靠 `entryId` 分组来替代 `BabyCloudEntry`。

- `lib/models/baby_cloud_source.dart`
  - 亲宝宝数据源模型。
  - 新增字段：
    - `libraryId`
    - `libraryName`
    - 阿里云盘 OAuth / token / drive 信息字段：`aliyunDriveClientId`、`aliyunDriveClientSecret`、`aliyunDriveRedirectUri`、`aliyunDriveScope`、`aliyunDriveAuthUrl`、`aliyunDriveTokenUrl`、`aliyunDriveAccessToken`、`aliyunDriveRefreshToken`、`aliyunDriveTokenExpiresAt`、`aliyunDriveDriveId`、`aliyunDriveUserId`、`aliyunDriveNickName`
  - 本地 `dataSourceId` 只代表一个本地配置，不代表云端库身份。

- `lib/models/baby_cloud_upload_task.dart`
  - 亲宝宝后台任务模型，继续承载上传任务，也承载元数据同步和永久删除任务。
  - `taskType`：`upload` / `metadata` / `purgeMedia` / `purgeEntry`。
  - `targetId`：非上传任务关联的动态 ID 或媒体 ID。

- `lib/services/storage_service.dart`
  - 注册 `BabyCloudEntryAdapter`，打开 `baby_cloud_entries` box。
  - 亲宝宝相关可选 box 仍走 recoverable box 逻辑，避免旧测试数据或模型变更导致核心启动失败。

### 云端身份和同步

核心服务在 `lib/services/baby_cloud_service.dart`。

云端根目录下会维护：

```text
library_manifest.json
babies/
  baby_xxx_宝宝名/
    index/album_index.json
    album/photos/yyyy/MM/...
    album/videos/yyyy/MM/...
    album/audios/yyyy/MM/...
    trash/
```

`library_manifest.json` 是云端库身份来源。它包含：

- `libraryId`
- `name`
- `rootPath`
- `deletePolicy`
- `babies`
  - `cloudBabyId`
  - `localBabyIds`
  - `name`
  - `safeName`
  - `babyDir`

重要原则：

- 同一个云端库必须以 `libraryId` 识别。
- 不要把本地 `dataSourceId` 当成云端身份。
- 同一个 WebDAV 根目录即使在不同设备或不同本地数据源配置里，也应通过相同 `libraryId` 合并展示。
- 宝宝目录只使用 manifest 里的 `babyDir`；没有 manifest 记录时创建最新版目录。
- 新目录命名使用 `cloudBabyId_safeName`，不再兼容旧的 `babyId_safeName` 目录。

同步流程：

1. 检测亲宝宝数据源可用性。WebDAV 走 `PROPFIND/MKCOL/PUT/GET/DELETE/MOVE`；阿里云盘走开放接口 token 刷新、文件列表、建目录、上传、下载、删除、移动。
2. 读取或创建 `library_manifest.json`。
3. 从 manifest 恢复当前宝宝的云端目录映射和 `cloudBabyId`。
4. 按 manifest 的 `babyDir` 读取最新版 `index/album_index.json`。
5. 如果远端 index 的 `format/type/libraryId/cloudBabyId` 都匹配当前 manifest，则先合并远端 index。
6. 发布 index 前再次读取远端 index 并合并，避免本地旧状态覆盖远端新内容。

不再执行的旧逻辑：

- 不扫描 `babies/` 下未登记在 manifest 中的目录。
- 不读取旧版或缺少 `type = starbank.baby_cloud.album_index` 的 index。
- 不在远端缺 index 时递归扫描 `album/photos|videos|audios` 裸文件导入。

冲突策略：

- 字段级最新版本优先。
- 媒体集合合并。
- 删除标记优先。
- `purgedAt` 标记优先，防止旧设备旧索引把已永久清理的内容复活。
- 本地路径只在本机可读时保留，不把其他设备的无效本地路径当成有效资源。

### 删除和回收站规则

这是最重要的安全规则：

- 默认永不物理删除云端文件。
- 普通删除只写：
  - `deletedAt`
  - `deleteReason`
  - `updatedAt`
- 删除整条动态：
  - `BabyCloudEntry.deleteReason = entryDeleted`
  - 动态下媒体也标记 `entryDeleted`
- 删除单文件：
  - 媒体标记 `singleFileDeleted`
  - 动态仍保留。
- 未来做媒体替换：
  - 被替换的旧媒体应标记 `deleteReason = replaced`
  - 写 `replacedByMediaId`
  - 不自动物理删除旧云端文件。
- 永久删除：
  - 只能从 `BabyCloudPermanentDeletePage` 进入。
  - 必须家长模式和密码确认。
  - 删除云端原文件后，不删除本地索引对象，而是写 `purgedAt`。
  - 保留 `purgedAt` 是为了多端同步时让删除事实继续传播。

不要恢复以下旧逻辑：

- 不要在回收站列表里直接放 `DELETE` 云端文件按钮。
- 不要在数据源页提供「删除云端宝宝目录」这类目录树删除入口。
- 不要在同步、切换数据源、清理任务、恢复数据时自动删除云端原文件。

### 数据源切换规则

当前实现：

- 切换数据源只改变当前亲宝宝功能内的数据源。
- 不清空本地旧数据。
- 切换后提示是否立即同步远端。
- 同步时按 `libraryId` 合并同一个云端库的数据。

后续如继续优化切换体验，应保留这些原则：

- 同一 `libraryId`：直接合并展示。
- 远端有旧结构但缺 manifest：按新版空库初始化 manifest；旧测试数据可由开发者在 WebDAV 上手动删除，不自动导入。
- 新空目录：初始化 manifest，但不要覆盖其他目录。
- 完全不同库：提示用户是切换查看、合并导入，还是稍后处理；不要自动删除本地或远端数据。

### WebDAV 规则

- 支持 HTTP 和 HTTPS。
- 外网地址和内网地址分别保存。
- 当前网络看起来在局域网时，优先检测内网地址；内网不可用时再检测外网。
- WebDAV 根目录不存在时应自动创建。
- 错误信息需要尽量包含完整请求尝试，尤其是 `PROPFIND/MKCOL/PUT/GET/DELETE` 的 URL、状态码和响应摘要。
- 用户已经反馈过 `/dav` 404、第二次请求路径不清晰、错误显示不完整等问题，后续改 WebDAV 时要特别小心路径拼接。

### 阿里云盘规则

- OAuth 授权必须先保存 source，再生成带 source id 的 state，回跳时校验 state 后把 token 写回同一个 source。
- 移动端不能假定一定能自动回跳；保留「粘贴 code」兜底入口。
- 支持自定义 Access Token 登录：没有 refresh token 时，服务层直接拿 access token 调开放接口校验；如果 401 或过期，提示用户重新填写或改用 OAuth。
- Refresh Token 更适合长期使用，但刷新 token 通常仍需要 Client ID；页面应把这个差异讲清楚。
- 阿里云盘底层客户端负责把远端路径解析成 `file_id`，上层仍只传 `/starbank_baby_cloud/...` 这类路径。
- 可用性检查要真实调用开放接口读取根目录或 drive 信息，不能只看本地 access token 是否过期。
- 路径不存在可以按不存在处理；token、权限、网络、API 错误必须向上传递，不能在删除或覆盖时被吞掉。
- 上传沿用分片上传：`openFile/create` 获取 `upload_url`，PUT 分片后 `openFile/complete`。

### 上传和目录规则

上传目录：

```text
album/photos/yyyy/MM
album/videos/yyyy/MM
album/audios/yyyy/MM
```

上传流程：

- 未配置可用数据源时，必须提示用户，不能创建假任务。
- 点击上传后应关闭选择器或编辑页，进入后台任务队列。
- 任务应支持暂停、继续、取消、删除、失败原因展示。
- 上传前用 SHA-256 判重。
- 判重要按当前云端库/当前宝宝判断，而不是只看本地 `dataSourceId`。
- 上传成功后要发布 index，并确保动态 `BabyCloudEntry` 和媒体 `BabyCloudMedia` 的关系同步更新。

### 后台任务规则

- 后台任务页统一展示上传、动态修改同步、永久删除。
- 编辑已有动态时，本地 `BabyCloudEntry` / `BabyCloudMedia` 立即更新，随后排 `metadata` 任务发布最新 index。
- 永久删除只在家长密码确认后排 `purgeEntry` / `purgeMedia` 任务；任务成功后才写 `purgedAt`。
- 后台任务失败时保留错误信息，用户可在任务页重试；不要在前台页面长时间等待 WebDAV I/O。

### Hive adapter 注意事项

本次新增/修改了 Hive 字段：

- `BabyCloudEntry`：typeId `51`
- `BabyCloudMedia`：新增字段 24-28
- `BabyCloudSource`：新增字段 16-17
- `BabyCloudSource`：阿里云盘新增字段 18-28
- `BabyCloudUploadTask`：新增字段 22-23（`taskType`、`targetId`）

正常应运行：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

但本次环境里 `build_runner` 曾超时，最后手动补齐了 adapter，并用 analyze/test/build 验证通过。以后修改 `@HiveType` / `@HiveField` 时必须：

1. 优先运行 build_runner。
2. 如果工具链因为沙箱或 Dart analytics 卡住，先设置临时环境变量：

```powershell
$env:APPDATA='D:\git\starBank\.tmp_appdata'
$env:LOCALAPPDATA='D:\git\starBank\.tmp_localappdata'
```

3. 如果仍无法生成，手动改 adapter 后必须跑完整验证。

### 验证记录

本轮最终验证：

```powershell
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --debug
```

结果：

- analyze 无新增 error，只剩项目既有 warning/info。
- flutter test 通过。
- debug APK 构建通过。
- 本机 debug APK 输出：

```text
build\app\outputs\flutter-apk\app-debug.apk
```

构建时如果遇到 `JAVA_HOME is not set`，本机可临时使用 Android Studio JBR：

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
```

## 后续开发检查清单

改亲宝宝云相册前，至少检查：

- 是否读过本文档。
- 是否保持 `libraryId` 作为云端库身份。
- 是否发布 index 前先读远端并合并。
- 是否没有任何自动物理删除云端文件的路径。
- 是否软删除、恢复、永久删除都写入正确标记。
- 是否同时维护 `BabyCloudEntry` 和 `BabyCloudMedia`。
- 是否切换数据源不会清空本地数据或覆盖远端数据。
- 是否新设备只配置 WebDAV 就能同步看到云端已有内容。
- 是否跑过 analyze、test；涉及 Android 能力时跑 debug APK 构建。
