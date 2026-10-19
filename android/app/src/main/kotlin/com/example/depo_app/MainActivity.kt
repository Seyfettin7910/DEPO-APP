package com.example.depo_app

import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Uygulama içi güncelleme: indirilen APK, Android'in PackageInstaller
 * servisiyle kurulur. Android 12+ cihazlarda, uygulama kendini bir kez
 * güncelledikten sonra sonraki güncellemeler (üreticinin izin verdiği
 * telefonlarda) kullanıcıya sormadan kurulabilir.
 *
 * İndirme, Android'in kendi indirme yöneticisiyle (DownloadManager) yapılır:
 * uygulama arka plana düşse, hatta kapatılsa da indirme sürer; bildirim
 * çubuğunda ilerleme görünür.
 */
class MainActivity : FlutterActivity() {
    /** "Güncelleme indi · kurmak için dokun" bildirimiyle açıldı mı? */
    private var bildirimdenKurulum = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        niyetiOku(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        niyetiOku(intent)
    }

    private fun niyetiOku(niyet: Intent?) {
        if (niyet?.getBooleanExtra(Bildirimler.KUR_EKI, false) == true) {
            bildirimdenKurulum = true
            niyet?.removeExtra(Bildirimler.KUR_EKI)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "depo_takip/guncelleme")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "kurulumIzniVarMi" -> result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                            packageManager.canRequestPackageInstalls()
                        else true
                    )
                    "kurulumIzniIste" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        }
                        result.success(null)
                    }
                    "apkKur" -> {
                        val yol = call.argument<String>("yol")
                        if (yol == null) {
                            result.error("YOL", "APK yolu yok", null)
                        } else {
                            try {
                                apkKur(yol)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("KURULUM", e.message, null)
                            }
                        }
                    }
                    "pilAyari" -> {
                        // Arka plan bildirim kontrolü pil tasarrufu yüzünden
                        // gecikmesin: "kısıtlama yok" izni ekranı.
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                        result.success(null)
                    }
                    "indirmeKlasoru" -> result.success(
                        getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)?.absolutePath
                    )
                    "indirmeBaslat" -> {
                        try {
                            result.success(
                                indirmeBaslat(
                                    call.argument<String>("url")!!,
                                    call.argument<String>("ad")!!,
                                    call.argument<String>("baslik") ?: "Güncelleme",
                                    call.argument<Boolean>("sadeceWifi") ?: false,
                                )
                            )
                        } catch (e: Exception) {
                            result.error("INDIRME", e.message, null)
                        }
                    }
                    "indirmeDurumu" -> {
                        val id = call.argument<Number>("id")?.toLong()
                        if (id == null) result.success(mapOf("durum" to "yok"))
                        else try {
                            result.success(indirmeDurumu(id))
                        } catch (e: Exception) {
                            result.error("INDIRME", e.message, null)
                        }
                    }
                    "bildirimdenKurulum" -> {
                        result.success(bildirimdenKurulum)
                        bildirimdenKurulum = false
                    }
                    "indirmeIptal" -> {
                        val id = call.argument<Number>("id")?.toLong()
                        if (id != null) {
                            try { indirmeYoneticisi().remove(id) } catch (_: Exception) {}
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun indirmeYoneticisi() =
        getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    private fun indirmeBaslat(url: String, ad: String, baslik: String, sadeceWifi: Boolean): Long {
        val klasor = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: throw IllegalStateException("İndirme klasörü yok")
        File(klasor, ad).delete() // aynı ad varsa yönetici "-1" ekler; önce sil
        val istek = DownloadManager.Request(Uri.parse(url))
            .setTitle(baslik)
            .setDescription("Uygulama güncellemesi indiriliyor")
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, ad)
            .setAllowedOverMetered(!sadeceWifi)
            .setAllowedOverRoaming(!sadeceWifi)
        return indirmeYoneticisi().enqueue(istek)
    }

    private fun indirmeDurumu(id: Long): Map<String, Any?> {
        indirmeYoneticisi().query(DownloadManager.Query().setFilterById(id)).use { c ->
            if (c == null || !c.moveToFirst()) return mapOf("durum" to "yok")
            fun sayi(k: String) = c.getLong(c.getColumnIndexOrThrow(k))
            val durum = when (c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                DownloadManager.STATUS_SUCCESSFUL -> "bitti"
                DownloadManager.STATUS_FAILED -> "hata"
                DownloadManager.STATUS_PAUSED -> "duraklatildi"
                DownloadManager.STATUS_PENDING -> "bekliyor"
                else -> "calisiyor"
            }
            val yer = c.getString(c.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
            return mapOf(
                "durum" to durum,
                "alinan" to sayi(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR),
                "toplam" to sayi(DownloadManager.COLUMN_TOTAL_SIZE_BYTES),
                "sebep" to sayi(DownloadManager.COLUMN_REASON),
                "yol" to yer?.let { Uri.parse(it).path },
            )
        }
    }

    private fun apkKur(yol: String) {
        val kurucu = packageManager.packageInstaller
        val parametre = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            parametre.setRequireUserAction(
                PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED
            )
        }
        val oturumId = kurucu.createSession(parametre)
        kurucu.openSession(oturumId).use { oturum ->
            File(yol).inputStream().use { giris ->
                oturum.openWrite("Depo-Otomasyon-Sistemi.apk", 0, -1).use { cikis ->
                    giris.copyTo(cikis)
                    oturum.fsync(cikis)
                }
            }
            val niyet = Intent(this, KurulumAlici::class.java)
            var bayrak = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                bayrak = bayrak or PendingIntent.FLAG_MUTABLE
            }
            val bekleyen = PendingIntent.getBroadcast(this, oturumId, niyet, bayrak)
            oturum.commit(bekleyen.intentSender)
        }
    }
}

/** Kurulum sonucu: kullanıcı onayı gerekiyorsa sistemin onay ekranını açar. */
class KurulumAlici : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val durum = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -999)
        if (durum == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val onay = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            if (onay != null) {
                onay.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(onay)
            }
        }
    }
}

/** Uygulamanın kendi (yerel) bildirimleri: Flutter'daki kanalla aynı kanal. */
object Bildirimler {
    const val KANAL = "depo_bildirim"
    const val KUR_EKI = "guncelleme_kur"
    private const val INDI_NO = 7102
    private const val GUNCELLENDI_NO = 7103

    private fun goster(context: Context, no: Int, baslik: String, govde: String, kur: Boolean) {
        try {
            val yonetici =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                yonetici.getNotificationChannel(KANAL) == null
            ) {
                yonetici.createNotificationChannel(
                    NotificationChannel(KANAL, "Depo bildirimleri", NotificationManager.IMPORTANCE_HIGH)
                )
            }
            val ac = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                if (kur) putExtra(KUR_EKI, true)
            }
            var bayrak = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                bayrak = bayrak or PendingIntent.FLAG_IMMUTABLE
            }
            val dokun = PendingIntent.getActivity(context, no, ac, bayrak)
            var simge = context.resources.getIdentifier("ic_bildirim", "drawable", context.packageName)
            if (simge == 0) simge = context.applicationInfo.icon
            val kurucu = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, KANAL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
            }
            val bildirim = kurucu
                .setSmallIcon(simge)
                .setColor(0xFF2E6F40.toInt())
                .setContentTitle(baslik)
                .setContentText(govde)
                .setStyle(Notification.BigTextStyle().bigText(govde))
                .setContentIntent(dokun)
                .setAutoCancel(true)
                .build()
            yonetici.notify(no, bildirim)
        } catch (_: Exception) {
        }
    }

    fun indi(context: Context, surum: String?) = goster(
        context, INDI_NO,
        "Güncelleme indi" + (surum?.let { " · sürüm $it" } ?: ""),
        "Kurmak için dokunun. Yarım kalan işleriniz kaybolmaz.",
        kur = true,
    )

    fun guncellendi(context: Context, surum: String?) = goster(
        context, GUNCELLENDI_NO,
        "Uygulama güncellendi" + (surum?.let { " · sürüm $it" } ?: ""),
        "Açmak için dokunun. Yenilikler ilk açılışta gösterilir.",
        kur = false,
    )
}

/**
 * İndirme yöneticisi bir indirmeyi bitirince çağrılır. Bizim güncelleme
 * indirmemizse ve uygulama o an açık değilse "Güncelleme indi" bildirimi.
 */
class IndirmeAlici : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try {
            val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val bizim = try {
                prefs.getLong("flutter.guncelleme_indirme_id", -2L)
            } catch (_: ClassCastException) {
                -2L
            }
            if (id < 0 || id != bizim) return
            // Uygulama açıksa (son 90 sn içinde "ön planda" işareti) pencere
            // zaten uygulamanın içinde açılır.
            val onPlan = try {
                prefs.getLong("flutter.on_plan_ms", 0L)
            } catch (_: ClassCastException) {
                0L
            }
            if (System.currentTimeMillis() - onPlan < 90_000L) return
            val dm = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            dm.query(DownloadManager.Query().setFilterById(id)).use { c ->
                if (c == null || !c.moveToFirst()) return
                val durum = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                if (durum != DownloadManager.STATUS_SUCCESSFUL) return
            }
            Bildirimler.indi(context, prefs.getString("flutter.guncelleme_indirme_surum", null))
        } catch (_: Exception) {
        }
    }
}

/** Uygulama güncellenince (yeni sürüm kurulunca) "Güncellendi" bildirimi. */
class GuncellendiAlici : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val surum = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        } catch (_: Exception) {
            null
        }
        Bildirimler.guncellendi(context, surum)
    }
}
