package com.wrynn7.craterline.plugin.push

import android.content.Context

/** Stub used when the AAR is built without google-services.json: push is simply unavailable. */
internal object FcmBackend {
    const val COMPILED_IN: Boolean = false

    @Suppress("UNUSED_PARAMETER")
    fun isInitialised(context: Context): Boolean = false

    fun fetchToken(onDone: (token: String?, error: String?) -> Unit) {
        onDone(null, "push is not built into this app (no google-services.json at build time)")
    }
}
