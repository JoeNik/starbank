package com.example.star_bank

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/**
 * ColorOS 通知栏优化辅助类
 *
 * ColorOS 对通知栏的管理比较严格，需要特殊处理：
 * 1. 通知渠道需要设置为 IMPORTANCE_HIGH 或以上
 * 2. 需要显式设置 setShowBadge(true)
 * 3. 需要设置声音和振动（即使用户可以关闭）
 */
object ColorOSNotificationHelper {

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

            // 创建新渠道，使用 IMPORTANCE_DEFAULT 确保 ColorOS 显示
            val channel = NotificationChannel(
                channelId,
                "音乐播放",
                NotificationManager.IMPORTANCE_DEFAULT // ColorOS 需要至少 DEFAULT 级别
            ).apply {
                description = "控制音乐播放、暂停、切歌等操作"
                setShowBadge(true) // ColorOS 需要显式启用
                enableVibration(false) // 不振动
                setSound(null, null) // 静音（用户可自定义）
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }

            manager.createNotificationChannel(channel)
        }
    }
}
