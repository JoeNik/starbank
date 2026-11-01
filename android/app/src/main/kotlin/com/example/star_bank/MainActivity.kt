package com.example.star_bank

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var aliyunOAuthChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ColorOS 通知栏优化：确保音乐通知能正常显示
        ColorOSNotificationHelper.ensureAudioServiceChannel(this)

        // ColorOS 特殊处理：延迟再次确认渠道配置
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            ColorOSNotificationHelper.ensureAudioServiceChannel(this)
        }, 1000)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKGROUND_NETWORK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val activeCount = call.argument<Int>("activeCount") ?: 0
                        val title = call.argument<String>("title") ?: "StarBank 后台网络"
                        val text = call.argument<String>("text") ?: "正在处理后台网络任务"
                        BackgroundNetworkForegroundService.start(
                            this,
                            activeCount,
                            title,
                            text,
                        )
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("START_BACKGROUND_NETWORK_FAILED", error.message, null)
                    }
                }

                "stop" -> {
                    try {
                        BackgroundNetworkForegroundService.stop(this)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("STOP_BACKGROUND_NETWORK_FAILED", error.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        aliyunOAuthChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ALIYUN_OAUTH_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialUri" -> result.success(extractAliyunOAuthUri(intent))
                    else -> result.notImplemented()
                }
            }
        }
        dispatchAliyunOAuthIntent(intent)

        // 公共下载目录写入通道(MediaStore / 旧版直写),音频文件落盘在子线程做,避免卡主线程
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PUBLIC_STORAGE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkInt" -> result.success(android.os.Build.VERSION.SDK_INT)

                "saveToDownload" -> {
                    val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                    val fileName = call.argument<String>("fileName") ?: "file"
                    val subDir = call.argument<String>("subDir") ?: ""
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
                    Thread {
                        try {
                            val savedName = saveToPublicDownload(bytes, fileName, subDir, mime)
                            mainHandler.post { result.success(savedName) }
                        } catch (error: Exception) {
                            mainHandler.post {
                                result.error("SAVE_TO_DOWNLOAD_FAILED", error.message, null)
                            }
                        }
                    }.start()
                }

                else -> result.notImplemented()
            }
        }
    }

    /// 把字节保存到公共下载目录 Download/<subDir>,返回实际落盘文件名。
    /// API 29+ 走 MediaStore.Downloads(无需存储权限,系统自动重名去重);
    /// 更早版本直接写公共 Download 目录(依赖已授予的 WRITE_EXTERNAL_STORAGE)。
    private fun saveToPublicDownload(
        bytes: ByteArray,
        fileName: String,
        subDir: String,
        mime: String,
    ): String {
        val safeSub = subDir.trim('/').replace("..", "")
        return if (android.os.Build.VERSION.SDK_INT >= 29) {
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mime)
                put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, "Download/$safeSub")
                put(android.provider.MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(
                android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values,
            ) ?: throw IllegalStateException("MediaStore 插入失败")
            try {
                resolver.openOutputStream(uri)?.use { it.write(bytes) }
                    ?: throw IllegalStateException("无法打开输出流")
                values.clear()
                values.put(android.provider.MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                runCatching { resolver.delete(uri, null, null) }
                throw e
            }
            // MediaStore 自动重名去重(追加 " (1)"),查回实际落盘名
            resolver.query(
                uri,
                arrayOf(android.provider.MediaStore.MediaColumns.DISPLAY_NAME),
                null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(android.provider.MediaStore.MediaColumns.DISPLAY_NAME)
                    if (idx >= 0) return cursor.getString(idx)
                }
            }
            fileName
        } else {
            val base = android.os.Environment.getExternalStoragePublicDirectory(
                android.os.Environment.DIRECTORY_DOWNLOADS,
            )
            val dir = if (safeSub.isEmpty()) base else java.io.File(base, safeSub)
            if (!dir.exists() && !dir.mkdirs()) {
                throw IllegalStateException("无法创建目录 ${dir.absolutePath}")
            }
            var target = java.io.File(dir, fileName)
            var n = 1
            while (target.exists()) {
                val dot = fileName.lastIndexOf('.')
                val stem = if (dot > 0) fileName.substring(0, dot) else fileName
                val ext = if (dot > 0) fileName.substring(dot) else ""
                target = java.io.File(dir, "$stem ($n)$ext")
                n++
            }
            java.io.FileOutputStream(target).use { it.write(bytes) }
            target.name
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        dispatchAliyunOAuthIntent(intent)
    }

    private fun dispatchAliyunOAuthIntent(intent: Intent?) {
        val uri = extractAliyunOAuthUri(intent) ?: return
        aliyunOAuthChannel?.invokeMethod("oauthRedirect", uri)
    }

    private fun extractAliyunOAuthUri(intent: Intent?): String? {
        val uri = intent?.data ?: return null
        if (uri.scheme != "starbank") return null
        if (uri.host != "aliyundrive") return null
        if (!uri.path.orEmpty().startsWith("/oauth")) return null
        return uri.toString()
    }

    companion object {
        private const val BACKGROUND_NETWORK_CHANNEL = "star_bank/background_network_service"
        private const val ALIYUN_OAUTH_CHANNEL = "star_bank/aliyun_oauth"
        private const val PUBLIC_STORAGE_CHANNEL = "star_bank/public_storage"
    }
}
