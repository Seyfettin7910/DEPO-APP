package com.example.depo_app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
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
 */
class MainActivity : FlutterActivity() {
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
                    else -> result.notImplemented()
                }
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
                oturum.openWrite("depo-takip.apk", 0, -1).use { cikis ->
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
