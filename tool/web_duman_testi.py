"""Web sürümünün duman testi (kontrol dalında, yayından önce).

build/web yerelde sunulur; masaüstü Chrome, iPhone Safari ve iPhone Chrome
kimlikleriyle açılır. Giriş yapılmaz (şifre gerekmez); sayfanın hatasız
yüklendiği, tarayıcı tanıma (tarayici.js), iPhone'da APK linkinin gizlendiği,
viewport ayarı denetlenir. Sorun varsa çıkış kodu 1 olur (derleme kırmızı).
"""
import subprocess
import sys
import time

from playwright.sync_api import sync_playwright

PORT = 8765
URL = f"http://localhost:{PORT}/"
IPHONE_SAFARI = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
                 "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 "
                 "Mobile/15E148 Safari/604.1")
IPHONE_CHROME = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
                 "AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/129.0.6668.69 "
                 "Mobile/15E148 Safari/604.1")

hatalar = []


def kontrol(kosul, mesaj):
    print(("TAMAM  " if kosul else "HATA   ") + mesaj, flush=True)
    if not kosul:
        hatalar.append(mesaj)


def ac(tarayici, ad, ua=None, mobil=False):
    ctx = tarayici.new_context(
        user_agent=ua,
        viewport={"width": 390, "height": 844} if mobil else {"width": 1280, "height": 900},
        is_mobile=mobil, has_touch=mobil, locale="tr-TR")
    if ua and "iPhone" in ua:
        # Gerçek iPhone'daki gibi navigator.platform da "iPhone" olsun.
        ctx.add_init_script(
            "Object.defineProperty(navigator, 'platform', {get: () => 'iPhone'});")
    sayfa = ctx.new_page()
    konsol = []
    sayfa.on("pageerror", lambda e: konsol.append(str(e)))
    sayfa.goto(URL, wait_until="load")
    # Flutter ilk kareyi çizince "yükleniyor" yazısı kalkar.
    for _ in range(60):
        if sayfa.evaluate("!document.getElementById('yukleniyor')"):
            break
        time.sleep(0.5)
    kontrol(sayfa.evaluate("!document.getElementById('yukleniyor')"),
            f"{ad}: uygulama açıldı (ilk kare çizildi)")
    time.sleep(3)  # açılış ekranı → giriş ekranı
    # Erişilebilirlik ağacını aç: ekrandaki yazılar DOM'da görünür olsun.
    sayfa.evaluate("""() => { const p = document.querySelector('flt-semantics-placeholder');
                              if (p) p.click(); }""")
    time.sleep(2)
    sayfa.screenshot(path=f"duman_{ad}.png")
    kontrol(not konsol, f"{ad}: sayfa hatası yok {konsol[:2] if konsol else ''}")
    return ctx, sayfa


def metin(sayfa):
    return sayfa.evaluate("""() => {
        const parcalar = [];
        document.querySelectorAll('flt-semantics, [aria-label]').forEach(e => {
          if (e.getAttribute('aria-label')) parcalar.push(e.getAttribute('aria-label'));
          if (e.textContent) parcalar.push(e.textContent);
        });
        return parcalar.join(' | ');
    }""")


def main():
    sunucu = subprocess.Popen([sys.executable, "-m", "http.server", str(PORT)],
                              cwd="build/web", stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL)
    time.sleep(1.5)
    try:
        with sync_playwright() as p:
            t = p.chromium.launch()

            ctx, s = ac(t, "masaustu_chrome")
            yazi = metin(s)
            kontrol("DEPO OTOMASYON" in yazi, "masaüstü: giriş ekranı yazısı görünüyor")
            kontrol("Android uygulamasını indir" in yazi,
                    "masaüstü: Android APK linki görünüyor")
            kontrol(s.evaluate("depoTarayiciAdi()") == "Chrome",
                    "masaüstü: tarayıcı Chrome olarak tanındı")
            kontrol(s.evaluate("depoIos()") is False, "masaüstü: iOS değil")
            vp = s.evaluate("document.querySelector('meta[name=viewport]').content")
            kontrol("maximum-scale=1" in vp, f"viewport büyütme kapalı ({vp})")
            ctx.close()

            ctx, s = ac(t, "iphone_safari", IPHONE_SAFARI, mobil=True)
            yazi = metin(s)
            kontrol(s.evaluate("depoTarayiciAdi()") == "Safari",
                    "iPhone: Safari olarak tanındı")
            kontrol(s.evaluate("depoIos()") is True, "iPhone: iOS olarak tanındı")
            kontrol("DEPO OTOMASYON" in yazi, "iPhone: giriş ekranı yazısı görünüyor")
            kontrol("Android uygulamasını indir" not in yazi,
                    "iPhone: APK linki gizli")
            ctx.close()

            ctx, s = ac(t, "iphone_chrome", IPHONE_CHROME, mobil=True)
            kontrol(s.evaluate("depoTarayiciAdi()") == "Chrome",
                    "iPhone Chrome: Chrome olarak tanındı (Safari uyarısı çıkar)")
            ctx.close()
            t.close()
    finally:
        sunucu.terminate()

    if hatalar:
        print("::error title=Web duman testi::" + " / ".join(hatalar))
        sys.exit(1)
    print("::notice title=Web duman testi::Hepsi tamam")


if __name__ == "__main__":
    main()
