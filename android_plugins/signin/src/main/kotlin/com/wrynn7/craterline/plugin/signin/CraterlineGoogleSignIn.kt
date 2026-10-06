package com.wrynn7.craterline.plugin.signin

import android.app.Activity
import android.content.pm.PackageManager
import android.os.CancellationSignal
import android.util.Log
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.GetCredentialInterruptedException
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException
import androidx.credentials.exceptions.GetCredentialUnsupportedException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import java.util.concurrent.Executors
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Godot singleton "CraterlineGoogleSignIn": Sign in with Google through Android Credential Manager.
 * GDScript wrapper: GoogleSignIn. The game then sends the ID token to Firebase (Identity Toolkit signInWithIdp).
 *
 * Methods: is_available(), sign_in(web_client_id, nonce), sign_out()
 * Signals: sign_in_succeeded(id_token, email, display_name), sign_in_failed(code, message),
 *          sign_out_finished()
 * Failure codes: "cancelled" (player backed out), "no_credential" (no Google account on the device),
 *   "unavailable" (no Play services / Credential Manager), "network", "config" (web client id wrong or not set up),
 *   "bad_token" (Google answered with something we could not read), "error".
 */
class CraterlineGoogleSignIn(godot: Godot) : GodotPlugin(godot) {

    companion object {
        const val TAG = "CraterlineGoogleSignIn"
        const val PLUGIN_NAME = "CraterlineGoogleSignIn"

        /** Maps a Credential Manager exception to one of the codes above. Kept pure so it is easy to reason about. */
        fun codeFor(e: GetCredentialException): String =
            when {
                e is GetCredentialCancellationException -> "cancelled"
                e is NoCredentialException -> "no_credential"
                e is GetCredentialProviderConfigurationException || e is GetCredentialUnsupportedException -> "unavailable"
                e is GetCredentialInterruptedException -> "network"
                // 28444 = "Developer console is not set up correctly": wrong web client id or SHA-1 not registered.
                (e.message ?: "").contains("28444") || (e.message ?: "").contains("not set up correctly") -> "config"
                else -> "error"
            }
    }

    private val succeeded = SignalInfo("sign_in_succeeded", String::class.java, String::class.java, String::class.java)
    private val failed = SignalInfo("sign_in_failed", String::class.java, String::class.java)
    private val signedOut = SignalInfo("sign_out_finished")
    private val executor = Executors.newSingleThreadExecutor()

    @Volatile
    private var busy: Boolean = false

    override fun getPluginName(): String = PLUGIN_NAME

    override fun getPluginSignals(): MutableSet<SignalInfo> = mutableSetOf(succeeded, failed, signedOut)

    @UsedByGodot
    fun is_available(): Boolean {
        val context = activity ?: return false
        return try {
            context.packageManager.getPackageInfo("com.google.android.gms", 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    @UsedByGodot
    fun sign_in(webClientId: String, nonce: String) {
        val host: Activity? = activity
        if (host == null || webClientId.isEmpty()) {
            emitSignal(failed.name, if (host == null) "unavailable" else "config", "no activity or web client id")
            return
        }
        if (busy) {
            emitSignal(failed.name, "error", "a sign-in is already running")
            return
        }
        busy = true
        // Credential Manager shows UI and must be started from the main thread.
        host.runOnUiThread {
            try {
                val option = GetSignInWithGoogleOption.Builder(webClientId)
                    .apply { if (nonce.isNotEmpty()) setNonce(nonce) }
                    .build()
                val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
                CredentialManager.create(host).getCredentialAsync(
                    host, request, CancellationSignal(), executor,
                    object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                        override fun onResult(result: GetCredentialResponse) = handleResult(result)
                        override fun onError(e: GetCredentialException) = fail(codeFor(e), e.message)
                    }
                )
            } catch (e: Exception) {
                Log.w(TAG, "sign-in could not start", e)
                fail("error", e.message)
            }
        }
    }

    @UsedByGodot
    fun sign_out() {
        val host = activity
        if (host == null) {
            emitSignal(signedOut.name)
            return
        }
        host.runOnUiThread {
            try {
                CredentialManager.create(host).clearCredentialStateAsync(
                    ClearCredentialStateRequest(), CancellationSignal(), executor,
                    object : CredentialManagerCallback<Void?, ClearCredentialException> {
                        override fun onResult(result: Void?) = emitSignal(signedOut.name)
                        override fun onError(e: ClearCredentialException) = emitSignal(signedOut.name)
                    }
                )
            } catch (e: Exception) {
                emitSignal(signedOut.name)
            }
        }
    }

    private fun handleResult(result: GetCredentialResponse) {
        val credential = result.credential
        if (credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            try {
                val google = GoogleIdTokenCredential.createFrom(credential.data)
                busy = false
                emitSignal(succeeded.name, google.idToken, google.id, google.displayName ?: "")
            } catch (e: GoogleIdTokenParsingException) {
                fail("bad_token", e.message)
            }
        } else {
            fail("bad_token", "unexpected credential type " + credential.type)
        }
    }

    private fun fail(code: String, message: String?) {
        busy = false
        emitSignal(failed.name, code, message ?: "")
    }
}
