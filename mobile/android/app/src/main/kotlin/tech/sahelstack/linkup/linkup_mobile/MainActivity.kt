package tech.sahelstack.linkup.linkup_mobile

import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.wifi.WifiManager
import android.net.wifi.WifiManager.MulticastLock
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException

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
        // tél↔tél (Mode Hôte) : liste les apps installées (nom, icône, chemin de
        // l'APK) pour pouvoir ENVOYER une app à un autre téléphone, façon Xender.
        private const val APPS_CHANNEL = "linkup/apps"
        private const val ICON_PX = 96
        // Sauvegarde d'un fichier (PDF, audio…) dans le dossier PUBLIC
        // « Téléchargements/LinkUp », visible par l'utilisateur dans son
        // explorateur de fichiers (via MediaStore sur Android 10+).
        private const val SAVE_CHANNEL = "linkup/savefile"
        private const val PUBLIC_SUBDIR = "LinkUp"
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

        // tél↔tél — liste des apps installées (exécutée hors thread UI : l'énumération
        // + le rendu des icônes peuvent prendre quelques centaines de ms).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APPS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> Thread {
                    val apps = try {
                        listInstalledApps()
                    } catch (e: Exception) {
                        null
                    }
                    runOnUiThread {
                        if (apps != null) result.success(apps)
                        else result.error("APPS_LIST_FAILED", "Énumération des apps impossible", null)
                    }
                }.start()
                else -> result.notImplemented()
            }
        }

        // Sauvegarde publique (Téléchargements/LinkUp) — exécutée hors thread UI
        // car la copie peut prendre un peu de temps sur un gros fichier.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAVE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val srcPath = call.argument<String>("srcPath")
                    val filename = call.argument<String>("filename")
                    val mime = call.argument<String>("mime")
                    if (srcPath == null || filename == null) {
                        result.error("BAD_ARGS", "srcPath/filename requis", null)
                    } else {
                        Thread {
                            val location = try {
                                saveToDownloads(srcPath, filename, mime)
                            } catch (e: Exception) {
                                null
                            }
                            runOnUiThread {
                                if (location != null) result.success(location)
                                else result.error("SAVE_FAILED", "Enregistrement impossible", null)
                            }
                        }.start()
                    }
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

    /**
     * Liste les applications LANCEABLES installées par l'utilisateur (on exclut
     * les apps système non mises à jour, et soi-même), avec leur nom, version,
     * taille de l'APK, chemin de l'APK (base.apk lisible par le Dart) et icône
     * (PNG base64). C'est ce que LinkUp envoie à un autre téléphone, comme Xender.
     */
    private fun listInstalledApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = pm.queryIntentActivities(launcher, 0)
        val seen = HashSet<String>()
        val apps = ArrayList<Map<String, Any?>>()
        for (ri in resolved) {
            val ai = ri.activityInfo?.applicationInfo ?: continue
            val pkg = ai.packageName
            if (pkg == packageName) continue                 // ne pas se proposer soi-même
            if (!seen.add(pkg)) continue                     // dédoublonne (multi-activités)
            val isSystem = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            val isUpdatedSystem = (ai.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
            if (isSystem && !isUpdatedSystem) continue        // on garde les apps « utilisateur »
            val apkPath = ai.sourceDir ?: continue
            val size = try { File(apkPath).length() } catch (e: Exception) { 0L }
            val versionName = try { pm.getPackageInfo(pkg, 0).versionName } catch (e: Exception) { null }
            val icon = try { drawableToBase64Png(pm.getApplicationIcon(ai)) } catch (e: Exception) { null }
            apps.add(
                mapOf(
                    "name" to pm.getApplicationLabel(ai).toString(),
                    "package" to pkg,
                    "versionName" to versionName,
                    "sizeBytes" to size,
                    "apkPath" to apkPath,
                    "icon" to icon,
                )
            )
        }
        apps.sortBy { (it["name"] as? String)?.lowercase() ?: "" }
        return apps
    }

    /**
     * Enregistre [srcPath] dans le dossier PUBLIC « Téléchargements/LinkUp » sous
     * le nom [filename], et renvoie un emplacement lisible (« Téléchargements/LinkUp/… »).
     *
     * Android 10+ : via MediaStore.Downloads (aucune permission requise, fichier
     * visible et indexé). Avant : chemin direct dans le dossier Download public
     * (nécessite WRITE_EXTERNAL_STORAGE, déclarée maxSdk 28 au manifest).
     */
    private fun saveToDownloads(srcPath: String, filename: String, mime: String?): String {
        val safeName = filename.substringAfterLast('/').ifEmpty { "fichier" }
        val src = File(srcPath)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, safeName)
                if (!mime.isNullOrEmpty()) put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/" + PUBLIC_SUBDIR
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("MediaStore insert a échoué")
            resolver.openOutputStream(uri).use { out ->
                if (out == null) throw IOException("OutputStream null")
                src.inputStream().use { it.copyTo(out) }
            }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Téléchargements/$PUBLIC_SUBDIR/$safeName"
        } else {
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                PUBLIC_SUBDIR
            )
            if (!dir.exists()) dir.mkdirs()
            val dest = File(dir, safeName)
            src.inputStream().use { input -> dest.outputStream().use { input.copyTo(it) } }
            return "Téléchargements/$PUBLIC_SUBDIR/$safeName"
        }
    }

    /** Rend une icône (y compris adaptive) en PNG base64 pour l'afficher côté Dart. */
    private fun drawableToBase64Png(drawable: Drawable): String {
        val bitmap = Bitmap.createBitmap(ICON_PX, ICON_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, ICON_PX, ICON_PX)
        drawable.draw(canvas)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }

    override fun onDestroy() {
        releaseLock()
        clipListener?.let { clipboardManager?.removePrimaryClipChangedListener(it) }
        clipListener = null
        super.onDestroy()
    }
}
