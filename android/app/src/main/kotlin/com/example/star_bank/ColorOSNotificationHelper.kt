package com.example.star_bank

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/**
 * ColorOS 通知栏优化辅助类
 *
 * ColorOS 对通知栏的管理比较严格，需要特殊处理：
 * 1. 通知渠道需要设置为 IMPORTANCE_HIGH
 * 2. 需要显式设置 setShowBadge(true)
 * 3. 必须设置声音（即使是系统默认声音）
 * 4. 需要发送一次"激活"通知来唤醒系统
 */
object ColorOSNotificationHelper {
    private const val TAG = "ColorOSNotification"

    /**
     * 为 AudioService 创建优化的通知渠道
     * 确保在 ColorOS 上也能正常显示下拉通知栏
     */
    fun ensureAudioServiceChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        // 检查 audio_service 的所有可能的渠道 ID
        val channelIds = listOf(
            "com.starbank.app.channel.audio.v7",
            "com.starbank.app.channel.audio.v6",
            "com.ryanheise.audioservice.channel.media" // audio_service 默认渠道
        )

        for (channelId in channelIds) {
            val existingChannel = manager.getNotificationChannel(channelId)
            if (existingChannel != null) {
                // 如果渠道已存在但重要性不够，删除并重建
                if (existingChannel.importance < NotificationManager.IMPORTANCE_DEFAULT) {
                    manager.deleteNotificationChannel(channelId)
                } else {
                    continue // 渠道已正确配置
                }
            }

            // 创建新渠道，使用 IMPORTANCE_HIGH 确保 ColorOS 下拉通知栏显示
            val channel = NotificationChannel(
                channelId,
                "音乐播放",
                NotificationManager.IMPORTANCE_HIGH // ColorOS 需要 HIGH 才显示在下拉栏
            ).apply {
                description = "控制音乐播放、暂停、切歌等操作"
                setShowBadge(true) // ColorOS 需要显式启用
                enableVibration(false) // 不振动
                // ColorOS 特殊要求：必须设置声音（即使是静音），否则不显示
                setSound(
                    android.provider.Settings.System.DEFAULT_NOTIFICATION_URI,
                    android.media.AudioAttributes.Builder()
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                        .build()
                )
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }

            manager.createNotificationChannel(channel)

            // ColorOS 特殊处理：发送一次隐形的测试通知来"激活"渠道
            // 这确保系统真正注册了该渠道，并允许后续通知显示
            sendActivationNotification(context, manager, channelId)
        }
    }

    /**
     * 发送一个临时的"激活"通知，然后立即取消
     * 这是 ColorOS 的一个已知 workaround：第一次使用渠道时需要先"激活"它
     */
    private fun sendActivationNotification(
        context: Context,
        manager: NotificationManager,
        channelId: String
    ) {
        try {
            val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                android.app.Notification.Builder(context, channelId)
            } else {
                @Suppress("DEPRECATION")
                android.app.Notification.Builder(context)
            }.apply {
                setContentTitle("StarBank")
                setContentText("音乐播放已就绪")
                setSmallIcon(android.R.drawable.ic_media_play)
                setAutoCancel(true)
                setTimeoutAfter(100) // 100ms 后自动消失

                // ColorOS 特殊要求：必须设置优先级
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    setPriority(android.app.Notification.PRIORITY_HIGH)
                }
            }.build()

            // 发送通知
            manager.notify(9999, notification)

            // 立即取消（100ms 后）
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                manager.cancel(9999)
            }, 100)

            android.util.Log.d(TAG, "Activation notification sent for channel: $channelId")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to send activation notification", e)
        }
    }
}
