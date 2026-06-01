package tech.sahelstack.linkup.linkup_mobile

import android.content.ClipboardManager
import android.content.Context
import android.net.wifi.WifiManager
import android.net.wifi.WifiManager.MulticastLock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity expose un MethodChannel `linkup/multicast` qui permet au code
 * Dart d'acquerir et liberer un WifiManager.MulticastLock.
 *
 * Sans ce verrou, Android filtre les paquets multicast UDP 5353 (mDNS) en
 * arriere-plan et la decouverte zeroconf echoue silencieusement.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "linkup/multicast"
        // EventChannel S5 : notifie Dart à chaque changement du presse-papier
        // (uniquement quand l'app est au 1er plan — Android interdit l'écoute
        // en arrière-plan depuis Android 10).
        private const val CLIPBOARD_EVENTS = "linkup/clipboard_events"
        // Tag visible dans `adb shell dumpsys wifi` / `dumpsys power` pour
        // identifier qui détient le verrou.
        private const val LOCK_TAG = "linkup-mdns-mobile"
    }

    private var multicastLock: MulticastLock? = null
    private var clipboardManager: ClipboardManager? = null
    private var clipListener: ClipboardManager.OnPrimaryClipChangedListener? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    acquireLock()
                    result.success(multicastLock?.isHeld == true)
                }
                "release" -> {
                    releaseLock()
                    result.success(true)
                }
                "isHeld" -> {
                    result.success(multicastLock?.isHeld == true)
                }
                else -> result.notImplemented()
            }
        }

        // S5 — presse-papier auto : on enregistre un OnPrimaryClipChangedListener
        // quand Dart commence à écouter (mode auto activé) et on le retire à
        // l'annulation. Le listener ne se déclenche QUE si l'app a le focus
        // (restriction Android 10+) — c'est l'auto « 1er plan », comme KDE Connect.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CLIPBOARD_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    val cm = applicationContext.getSystemService(Context.CLIPBOARD_SERVICE)
                        as ClipboardManager
                    val listener = ClipboardManager.OnPrimaryClipChangedListener {
                        events?.success(null)
                    }
                    cm.addPrimaryClipChangedListener(listener)
                    clipboardManager = cm
                    clipListener = listener
                }

                override fun onCancel(arguments: Any?) {
                    clipListener?.let { clipboardManager?.removePrimaryClipChangedListener(it) }
                    clipListener = null
                }
            })
    }

    private fun acquireLock() {
        if (multicastLock?.isHeld == true) {
            return
        }
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = wifiManager.createMulticastLock(LOCK_TAG)
        lock.setReferenceCounted(false)
        lock.acquire()
        multicastLock = lock
    }

    private fun releaseLock() {
        multicastLock?.takeIf { it.isHeld }?.release()
        multicastLock = null
    }

    override fun onDestroy() {
        releaseLock()
        clipListener?.let { clipboardManager?.removePrimaryClipChangedListener(it) }
        clipListener = null
        super.onDestroy()
    }
}
