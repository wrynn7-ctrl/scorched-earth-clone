package com.wrynn7.craterline.plugin.push

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging

/** The only place that touches Firebase (apart from CraterlinePushService), so the rest compiles in both flavours. */
internal object FcmBackend {
    const val COMPILED_IN: Boolean = true

    /** FirebaseInitProvider starts Firebase at process start from the generated google_app_id resources. */
    fun isInitialised(context: Context): Boolean =
        try {
            FirebaseApp.getApps(context).isNotEmpty()
        } catch (e: Throwable) {
            false
        }

    fun fetchToken(onDone: (token: String?, error: String?) -> Unit) {
        try {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (task.isSuccessful && !task.result.isNullOrEmpty()) {
                    onDone(task.result, null)
                } else {
                    onDone(null, task.exception?.message ?: "FCM returned no token")
                }
            }
        } catch (e: Throwable) {
            onDone(null, e.message ?: e.javaClass.simpleName)
        }
    }
}
