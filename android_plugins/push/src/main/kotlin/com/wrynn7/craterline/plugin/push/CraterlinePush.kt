package com.wrynn7.craterline.plugin.push

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.View
import androidx.core.app.OnNewIntentProvider
import androidx.core.util.Consumer
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONObject

/**
 * Godot singleton "CraterlinePush": Firebase Cloud Messaging for turn notifications. GDScript wrapper: PushService.
 *
 * Methods (snake_case on purpose, they are called from GDScript as written):
 *   is_available()                       true when FCM is built in, Firebase initialised and Google Play services exist
 *   refresh_token()                      asks FCM for the token; the answer arrives as token_changed / token_error
 *   get_token() -> String                last token seen ("" if none yet)
 *   has_notification_permission()        Android 13+ runtime permission (always true below 13)
 *   request_notification_permission()    shows the system dialog; the answer arrives as permission_result
 *   ensure_channel(name, description)    creates or renames the "turns" notification channel
 *   consume_launch_payload() -> String   JSON of the data of the notification that launched / reopened the app, once
 * Signals: token_changed(token), token_error(message), permission_result(granted), notification_opened(payload_json)
 *
 * The plugin never touches Firebase unless is_available() is true, so the same AAR logic runs in builds made
 * without google-services.json (then FcmBackend is a stub).
 */
class CraterlinePush(godot: Godot) : GodotPlugin(godot) {

    companion object {
        const val TAG = "CraterlinePush"
        const val PLUGIN_NAME = "CraterlinePush"
        const val CHANNEL_ID = "turns"
        private const val PERMISSION = "android.permission.POST_NOTIFICATIONS"
        private const val PERMISSION_REQUEST_CODE = 7301

        @Volatile
        var instance: CraterlinePush? = null

        /** True while the game's activity is resumed; the messaging service stays quiet then. */
        @Volatile
        var foreground: Boolean = false

        /** Creates the channel, or updates its visible name and description when text is given. API 26+ (our minSdk). */
        fun ensureChannel(context: Context, name: String?, description: String?) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            val existing = manager.getNotificationChannel(CHANNEL_ID)
            if (existing != null && name == null) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                name ?: existing?.name?.toString() ?: "Turns",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            channel.description = description ?: existing?.description ?: "It is your turn in an online match"
            manager.createNotificationChannel(channel)
        }

        /** Keys Android and Firebase add to a launch intent; everything else is the app's own data payload. */
        private fun isSystemKey(key: String): Boolean =
            key.startsWith("google.") || key.startsWith("gcm.") || key.startsWith("android.") ||
                key == "from" || key == "collapse_key" || key == "message_type"

        /** The data payload of a notification tap as a JSON object string, or null for a normal app launch. */
        fun payloadOf(extras: Bundle?): String? {
            if (extras == null || extras.isEmpty) return null
            val json = JSONObject()
            for (key in extras.keySet()) {
                if (isSystemKey(key)) continue
                val value = extras.get(key) ?: continue
                json.put(key, value.toString())
            }
            return if (json.length() == 0) null else json.toString()
        }
    }

    private val tokenChanged = SignalInfo("token_changed", String::class.java)
    private val tokenError = SignalInfo("token_error", String::class.java)
    private val permissionResult = SignalInfo("permission_result", Boolean::class.javaObjectType)
    private val notificationOpened = SignalInfo("notification_opened", String::class.java)

    @Volatile
    private var token: String = ""

    @Volatile
    private var pendingPayload: String? = null

    @Volatile
    private var mainLoopStarted: Boolean = false
    private var lastIntent: Intent? = null
    private val newIntentListener = Consumer<Intent> { intent -> handleIntent(intent) }

    init {
        instance = this
    }

    override fun getPluginName(): String = PLUGIN_NAME

    override fun getPluginSignals(): MutableSet<SignalInfo> =
        mutableSetOf(tokenChanged, tokenError, permissionResult, notificationOpened)

    // --- lifecycle ---------------------------------------------------------------------------------------------

    override fun onMainCreate(activity: Activity?): View? {
        if (activity != null) {
            try {
                ensureChannel(activity, null, null)
            } catch (e: Exception) {
                Log.w(TAG, "could not create the notification channel", e)
            }
            // Cold start: the intent that launched the activity. Warm start: ComponentActivity tells its listeners.
            handleIntent(activity.intent)
            (activity as? OnNewIntentProvider)?.addOnNewIntentListener(newIntentListener)
        }
        return null
    }

    override fun onGodotMainLoopStarted() {
        mainLoopStarted = true
    }

    override fun onMainResume() {
        foreground = true
    }

    override fun onMainPause() {
        foreground = false
    }

    override fun onMainDestroy() {
        (activity as? OnNewIntentProvider)?.removeOnNewIntentListener(newIntentListener)
        foreground = false
        if (instance === this) instance = null
    }

    // --- methods for GDScript ----------------------------------------------------------------------------------

    @UsedByGodot
    fun is_available(): Boolean {
        val context = activity ?: return false
        return FcmBackend.COMPILED_IN && playServicesInstalled(context) && FcmBackend.isInitialised(context)
    }

    @UsedByGodot
    fun get_token(): String = token

    @UsedByGodot
    fun refresh_token() {
        if (!is_available()) {
            emitSignal(tokenError.name, "push unavailable")
            return
        }
        FcmBackend.fetchToken { value, error ->
            if (value != null) deliverToken(value) else emitSignal(tokenError.name, error ?: "unknown error")
        }
    }

    @UsedByGodot
    fun has_notification_permission(): Boolean {
        val context = activity ?: return false
        if (Build.VERSION.SDK_INT < 33) return true
        return context.checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED
    }

    @UsedByGodot
    fun request_notification_permission() {
        val host = activity
        if (host == null) {
            emitSignal(permissionResult.name, false)
            return
        }
        if (has_notification_permission()) {
            emitSignal(permissionResult.name, true)
            return
        }
        host.runOnUiThread { host.requestPermissions(arrayOf(PERMISSION), PERMISSION_REQUEST_CODE) }
    }

    @UsedByGodot
    fun ensure_channel(name: String, description: String) {
        val context = activity ?: return
        try {
            ensureChannel(context, name.ifEmpty { null }, description.ifEmpty { null })
        } catch (e: Exception) {
            Log.w(TAG, "could not update the notification channel", e)
        }
    }

    @UsedByGodot
    fun consume_launch_payload(): String {
        val payload = pendingPayload ?: ""
        pendingPayload = null
        return payload
    }

    // --- internals ---------------------------------------------------------------------------------------------

    override fun onMainRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        emitSignal(permissionResult.name, granted)
    }

    internal fun deliverToken(value: String) {
        token = value
        emitSignal(tokenChanged.name, value)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null || intent === lastIntent) return
        lastIntent = intent
        // Android re-delivers the original intent when it recreates an activity from the recents screen.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        val payload = payloadOf(intent.extras) ?: return
        pendingPayload = payload
        // Before the engine runs there is nobody to tell; GDScript picks the payload up with consume_launch_payload().
        if (mainLoopStarted) emitSignal(notificationOpened.name, payload)
    }

    private fun playServicesInstalled(context: Context): Boolean =
        try {
            context.packageManager.getPackageInfo("com.google.android.gms", 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
}
