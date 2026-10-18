"""GitHub derlemesinde Android Gradle dosyalarını güncel Flutter şablonuyla
tazeler ve sürüm (release) imzasını ekler.

Kullanım: python3 tool/android_hazirla.py <flutter create ile üretilmiş şablon klasörü>

Repodaki android/ klasörü FlutLab için olduğu gibi kalır; bu betik yalnızca
derleme makinesinde çalışır. Uygulama kodu, manifest, ikonlar ve MainActivity
değişmez; yalnızca Gradle yapılandırması o anki Flutter sürümüne uyarlanır.
"""
import pathlib
import shutil
import sys

sablon = pathlib.Path(sys.argv[1]) / "android"
hedef = pathlib.Path("android")
assert sablon.is_dir(), f"Şablon bulunamadı: {sablon}"

# Eski Gradle dosyalarını (Groovy veya Kotlin) kaldır.
for ad in ["build.gradle", "build.gradle.kts", "settings.gradle",
           "settings.gradle.kts", "app/build.gradle", "app/build.gradle.kts"]:
    (hedef / ad).unlink(missing_ok=True)

# Şablondaki Gradle dosyalarını kopyala.
for ad in ["build.gradle", "build.gradle.kts", "settings.gradle",
           "settings.gradle.kts", "gradle.properties", "gradlew", "gradlew.bat",
           "app/build.gradle", "app/build.gradle.kts"]:
    kaynak = sablon / ad
    if kaynak.exists():
        shutil.copy2(kaynak, hedef / ad)
if (sablon / "gradle").is_dir():
    shutil.rmtree(hedef / "gradle", ignore_errors=True)
    shutil.copytree(sablon / "gradle", hedef / "gradle")

uygulama = hedef / "app/build.gradle.kts"
assert uygulama.exists(), "Beklenen app/build.gradle.kts şablonda yok"
metin = uygulama.read_text(encoding="utf-8")

imza = '''    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH") ?: error("ANDROID_KEYSTORE_PATH yok"))
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: "depo"
            keyPassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
        }
    }

    buildTypes {'''
assert metin.count("    buildTypes {") == 1, "buildTypes bloğu bulunamadı"
metin = metin.replace("    buildTypes {", imza, 1)

eski = 'signingConfig = signingConfigs.getByName("debug")'
assert eski in metin, "debug imza satırı bulunamadı"
metin = metin.replace(eski, 'signingConfig = signingConfigs.getByName("release")')

uygulama.write_text(metin, encoding="utf-8")
print("Android Gradle dosyaları hazır, release imzası eklendi.")
