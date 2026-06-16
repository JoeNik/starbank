package com.example.star_bank

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var aliyunOAuthChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }
}
