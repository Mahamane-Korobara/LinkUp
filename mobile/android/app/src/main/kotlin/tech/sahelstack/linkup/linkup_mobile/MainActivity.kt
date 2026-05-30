package tech.sahelstack.linkup.linkup_mobile

import android.content.Context
import android.net.wifi.WifiManager
import android.net.wifi.WifiManager.MulticastLock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
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
        private const val LOCK_TAG = "linkup-mdns"
    }

    private var multicastLock: MulticastLock? = null

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
        super.onDestroy()
    }
}
