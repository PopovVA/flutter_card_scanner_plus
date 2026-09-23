package dev.apissystems.flutter_card_scanner_plus

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Thin bridge to `android.nfc`: open a reader session, exchange APDUs, close.
 *
 * No EMV logic lives here. The Dart side decides what to send and how to read
 * the reply, which keeps that logic testable without a device.
 *
 * The plugin deliberately does not declare `android.permission.NFC` in its
 * manifest, so apps that never read cards do not inherit it. An app that wants
 * NFC adds the permission itself; without it this reports `nfcUnavailable`.
 */
class NfcSession(private val context: Context) {

    private val main = Handler(Looper.getMainLooper())
    private var activity: Activity? = null
    private var isoDep: IsoDep? = null
    private var pending: MethodChannel.Result? = null

    fun attach(activity: Activity?) {
        this.activity = activity
    }

    fun isAvailable(): Boolean {
        if (!hasPermission()) return false
        val adapter = NfcAdapter.getDefaultAdapter(context) ?: return false
        return adapter.isEnabled
    }

    fun connect(result: MethodChannel.Result) {
        val activity = activity
        if (activity == null) {
            result.error("nfcSessionError", "Plugin is not attached to an Activity", null)
            return
        }
        if (!hasPermission()) {
            result.error(
                "nfcUnavailable",
                "Add <uses-permission android:name=\"android.permission.NFC\" /> to the app manifest",
                null,
            )
            return
        }
        val adapter = NfcAdapter.getDefaultAdapter(context)
        if (adapter == null || !adapter.isEnabled) {
            result.error("nfcUnavailable", "NFC is off or not supported", null)
            return
        }

        close(null, null)
        pending = result
        try {
            adapter.enableReaderMode(
                activity,
                ::onTag,
                NfcAdapter.FLAG_READER_NFC_A or
                    NfcAdapter.FLAG_READER_NFC_B or
                    NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,
                null,
            )
        } catch (e: SecurityException) {
            pending = null
            result.error("nfcUnavailable", e.message, null)
        }
    }

    private fun onTag(tag: Tag) {
        val dep = IsoDep.get(tag)
        if (dep == null) {
            answer { it.error("nfcSessionError", "Tag is not ISO 7816", null) }
            return
        }
        try {
            dep.timeout = TIMEOUT_MS
            dep.connect()
            isoDep = dep
            answer { it.success(null) }
        } catch (e: Exception) {
            answer { it.error("nfcTagLost", e.message, null) }
        }
    }

    fun transceive(command: ByteArray, result: MethodChannel.Result) {
        val dep = isoDep
        if (dep == null || !dep.isConnected) {
            result.error("nfcTagLost", "No card is connected", null)
            return
        }
        // IsoDep.transceive blocks, so it must not run on the main thread.
        Thread {
            try {
                val reply = dep.transceive(command)
                main.post { result.success(reply) }
            } catch (e: Exception) {
                main.post { result.error("nfcTagLost", e.message, null) }
            }
        }.start()
    }

    fun close(message: String?, errorMessage: String?) {
        answer { it.error("nfcCancelled", "Session closed", null) }
        try {
            isoDep?.close()
        } catch (_: Exception) {
            // Already gone.
        }
        isoDep = null
        val activity = activity ?: return
        if (!hasPermission()) return
        try {
            NfcAdapter.getDefaultAdapter(context)?.disableReaderMode(activity)
        } catch (_: Exception) {
            // Nothing to disable.
        }
    }

    /** Calls the pending connect completion exactly once, on the main thread. */
    private fun answer(block: (MethodChannel.Result) -> Unit) {
        val result = pending ?: return
        pending = null
        main.post { block(result) }
    }

    private fun hasPermission(): Boolean =
        context.checkPermission(
            Manifest.permission.NFC,
            android.os.Process.myPid(),
            android.os.Process.myUid(),
        ) == PackageManager.PERMISSION_GRANTED

    private companion object {
        const val TIMEOUT_MS = 5_000
    }
}
