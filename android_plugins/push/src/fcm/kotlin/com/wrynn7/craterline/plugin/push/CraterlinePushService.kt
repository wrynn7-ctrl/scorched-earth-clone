package com.wrynn7.craterline.plugin.push

import android.app.Notification
import android.app.PendingIntent
import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Receives FCM events.
 *  - New token: handed to GDScript through the plugin (when it is running).
 *  - Message while the game is closed or in the background and the message has no "notification" part (a data-only
 *    message with `title` and `body` keys): shows a "Turns" notification whose tap carries the data keys.
 *    A message WITH a notification part is shown by Android itself and its data rides along in the tap intent.
 *  - Message while the game is in the foreground: ignored (the live connection already shows the news).
 */
class CraterlinePushService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        CraterlinePush.instance?.deliverToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (CraterlinePush.foreground) return
        val data = message.data
        val title = message.notification?.title ?: data["title"]
        val body = message.notification?.body ?: data["body"]
        if (title == null && body == null) return
        try {
            CraterlinePush.ensureChannel(this, null, null)
            val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            for ((k, v) in data) launch.putExtra(k, v)
            // One notification per match: a new turn replaces the previous one for the same match.
            val notificationId = (data["matchId"] ?: "turn").hashCode()
            val tap = PendingIntent.getActivity(
                this, notificationId, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val notification = Notification.Builder(this, CraterlinePush.CHANNEL_ID)
                .setSmallIcon(R.drawable.craterline_stat_turn)
                .setContentTitle(title)
                .setContentText(body)
                .setContentIntent(tap)
                .setAutoCancel(true)
                .build()
            val manager = getSystemService(android.app.NotificationManager::class.java)
            // Without the Android 13 permission notify() is a silent no-op; that is the player's choice.
            manager.notify(notificationId, notification)
        } catch (e: Exception) {
            Log.w(CraterlinePush.TAG, "could not show notification", e)
        }
    }
}
