package com.wrynn7.craterline.plugin.share

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.util.Log
import android.view.View
import androidx.core.app.OnNewIntentProvider
import androidx.core.util.Consumer
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Godot singleton "CraterlineShare": the Android share sheet and craterline:// deep links.
 * GDScript wrappers: ShareService and DeepLinks.
 *
 * Methods: share_text(title, text) -> bool, consume_pending_link() -> String
 * Signals: deep_link_received(url)
 *
 * Links reach the game through an <activity-alias> that the export plugin adds to the manifest. A link that opened a
 * closed game is kept until GDScript asks for it (consume_pending_link); a link that arrives while the game runs also
 * fires deep_link_received. The plugin only checks the scheme; DeepLinks (GDScript) validates the code.
 */
class CraterlineShare(godot: Godot) : GodotPlugin(godot) {

    companion object {
        const val TAG = "CraterlineShare"
        const val PLUGIN_NAME = "CraterlineShare"
        private const val SCHEME = "craterline"
    }

    private val linkReceived = SignalInfo("deep_link_received", String::class.java)

    @Volatile
    private var pendingLink: String? = null

    @Volatile
    private var mainLoopStarted: Boolean = false
    private var lastIntent: Intent? = null
    private val newIntentListener = Consumer<Intent> { intent -> handleIntent(intent) }

    override fun getPluginName(): String = PLUGIN_NAME

    override fun getPluginSignals(): MutableSet<SignalInfo> = mutableSetOf(linkReceived)

    override fun onMainCreate(activity: Activity?): View? {
        if (activity != null) {
            handleIntent(activity.intent)
            (activity as? OnNewIntentProvider)?.addOnNewIntentListener(newIntentListener)
        }
        return null
    }

    override fun onGodotMainLoopStarted() {
        mainLoopStarted = true
    }

    override fun onMainDestroy() {
        (activity as? OnNewIntentProvider)?.removeOnNewIntentListener(newIntentListener)
    }

    /** Opens the system share sheet with plain text. Returns false when there is nothing to show it with. */
    @UsedByGodot
    fun share_text(title: String, text: String): Boolean {
        val host = activity
        if (host == null || text.isEmpty()) return false
        host.runOnUiThread {
            try {
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                    if (title.isNotEmpty()) putExtra(Intent.EXTRA_SUBJECT, title)
                }
                host.startActivity(Intent.createChooser(send, title.ifEmpty { null }))
            } catch (e: ActivityNotFoundException) {
                Log.w(TAG, "no app can handle the share intent", e)
            }
        }
        return true
    }

    @UsedByGodot
    fun consume_pending_link(): String {
        val link = pendingLink ?: ""
        pendingLink = null
        return link
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null || intent === lastIntent) return
        lastIntent = intent
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        if (intent.action != Intent.ACTION_VIEW) return
        val data = intent.data ?: return
        if (data.scheme != SCHEME) return
        val url = data.toString()
        pendingLink = url
        if (mainLoopStarted) emitSignal(linkReceived.name, url)
    }
}
