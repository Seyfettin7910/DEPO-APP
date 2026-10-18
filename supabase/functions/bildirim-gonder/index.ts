// DEPO OTOMASYON SİSTEMİ — iPhone ve bilgisayar tarayıcısına bildirim gönderici.
//
// Supabase'de 2 dakikada bir (pg_cron) çağrılır. Yeni hareketlere ve durumlara
// bakar, her abonenin kendi ayarlarına göre bildirim (web push) gönderir.
// Android uygulaması bildirimlerini telefonda kendisi hesaplar; bu fonksiyon
// web / iPhone aboneleri içindir. Gizli anahtarlar ilk çalışmada burada
// üretilir ve veritabanında (uygulamanın okuyamadığı tabloda) saklanır.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { gonder, vapidAnahtarUret } from "./webpush.ts";

const KONU = "https://seyfettin7910.github.io/DEPO-APP/";
const SAAT_DILIMI = "Europe/Istanbul";
const GUN = 24 * 3600 * 1000;

// Telefondaki varsayılanlarla aynı ("gönderilmemiş kayıtlar" telefona özgü)
const VARSAYILAN_ACIK = [
  "kritikStok", "yeniAriza", "servisGecikmesi", "garantiBitiyor", "cihazGeldi",
  "depoyaGiris", "hurdaSilme", "servisDonus", "gunlukOzet",
];

type Satir = Record<string, any>;
interface Ayarlar {
  acik?: string[];
  servisGecikmeGun?: number;
  garantiGun?: number;
  izlenenDepolar?: string[];
  ozetSaat?: number;
  ozetDakika?: number;
}
interface Bildirim {
  tur: string;
  baslik: string;
  govde: string;
}

function v<T>(r: { data: T | null; error: any }): T {
  if (r.error) throw new Error(r.error.message ?? String(r.error));
  return r.data as T;
}

/** 1000'er satırlık sayfalarla tüm sonuçlar. */
async function tum(sorgu: (bas: number, bit: number) => PromiseLike<any>): Promise<Satir[]> {
  const out: Satir[] = [];
  for (let bas = 0; ; bas += 1000) {
    const parca = v<Satir[]>(await sorgu(bas, bas + 999));
    out.push(...parca);
    if (parca.length < 1000) break;
  }
  return out;
}

/** id -> satır sözlüğü (id listesi parçalara bölünerek sorgulanır). */
async function sozluk(db: SupabaseClient, tablo: string, kolonlar: string, idler: Iterable<string>) {
  const liste = [...new Set([...idler].filter(Boolean))];
  const m = new Map<string, Satir>();
  for (let i = 0; i < liste.length; i += 80) {
    const r = v<Satir[]>(await db.from(tablo).select(kolonlar).in("id", liste.slice(i, i + 80)));
    for (const x of r) m.set(String(x.id), x);
  }
  return m;
}

function yerel(t: Date) {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", {
    timeZone: SAAT_DILIMI, year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).formatToParts(t).map((x) => [x.type, x.value]));
  return { yil: +p.year, ay: +p.month, gun: +p.day, saat: +p.hour, dakika: +p.minute, anahtar: `${p.year}${p.month}${p.day}` };
}

/** İstanbul saatine göre bugünün başlangıcı (UTC ms). Türkiye UTC+3, yaz saati yok. */
function bugunBasi(t: Date): number {
  const y = yerel(t);
  return Date.UTC(y.yil, y.ay - 1, y.gun) - 3 * 3600 * 1000;
}

const tarihMetni = (ms: number) =>
  new Intl.DateTimeFormat("tr-TR", { timeZone: SAAT_DILIMI, day: "2-digit", month: "2-digit", year: "numeric" })
    .format(new Date(ms));
const saatMetni = (t: Date) =>
  new Intl.DateTimeFormat("tr-TR", { timeZone: SAAT_DILIMI, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" })
    .format(t);

Deno.serve(async (req) => {
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  try {
    const ayar = await ayarlariOku(db);
    if (!ayar.cron_anahtar || req.headers.get("x-cron-anahtar") !== ayar.cron_anahtar) {
      return new Response("yetkisiz", { status: 401 });
    }
    return Response.json(await calistir(db, ayar));
  } catch (e) {
    console.error(e);
    return new Response(String(e), { status: 500 });
  }
});

async function ayarlariOku(db: SupabaseClient): Promise<Record<string, string>> {
  const r = v<Satir[]>(await db.from("push_ayar").select("ad, deger"));
  return Object.fromEntries(r.map((x) => [x.ad, x.deger]));
}

async function ayarYaz(db: SupabaseClient, ad: string, deger: string) {
  v(await db.from("push_ayar").upsert({ ad, deger }));
}

async function calistir(db: SupabaseClient, ayar: Record<string, string>) {
  const simdi = new Date();
  const ms = simdi.getTime();

  // 1) Bildirim anahtarları (ilk çalışmada üretilir)
  if (!ayar.vapid_genel || !ayar.vapid_ozel) {
    const k = await vapidAnahtarUret();
    await ayarYaz(db, "vapid_ozel", k.ozelJwk);
    await ayarYaz(db, "vapid_genel", k.genel);
    ayar.vapid_genel = k.genel;
    ayar.vapid_ozel = k.ozelJwk;
  }
  const vapid = { genel: ayar.vapid_genel, ozelJwk: ayar.vapid_ozel, konu: KONU };

  // 2) İmleçler: ilk çalışmada mevcut kayıtlar için bildirim yapılmaz
  if (ayar.imlec_hareket === undefined) {
    const r = v<Satir[]>(await db.from("stok_hareketleri").select("synced_at").order("synced_at", { ascending: false }).limit(1));
    ayar.imlec_hareket = String(r[0]?.synced_at ?? 0);
    await ayarYaz(db, "imlec_hareket", ayar.imlec_hareket);
  }
  if (ayar.imlec_giris === undefined) {
    // giris_kayitlari tablosu yoksa (1.18.0 SQL'i çalıştırılmadıysa) 0'dan başlar
    const r = await db.from("giris_kayitlari").select("id").order("id", { ascending: false }).limit(1);
    ayar.imlec_giris = String(r.data?.[0]?.id ?? 0);
    await ayarYaz(db, "imlec_giris", ayar.imlec_giris);
  }

  const aboneler = v<Satir[]>(await db.from("push_abonelikleri").select("*"));

  // 3) Yeni hareketler (sunucuya ulaşma sırasına göre)
  const hamHareket = v<Satir[]>(await db.from("stok_hareketleri")
    .select("id, tip, tarih, sebep, not_, kullanici_id, depo_id, hedef_depo_id, cihaz_id, urun_id, synced_at")
    .gt("synced_at", Number(ayar.imlec_hareket)).eq("deleted", 0)
    .order("synced_at").limit(1000));
  let yeniImlec = Number(ayar.imlec_hareket);
  for (const h of hamHareket) yeniImlec = Math.max(yeniImlec, Number(h.synced_at));

  // Aynı hareket iki kez işlenmesin (tekrar gönderilen kayıtlar)
  let hareketler: Satir[] = [];
  const taze = hamHareket.filter((h) => ms - Number(h.tarih) < 3 * GUN);
  for (let i = 0; i < taze.length; i += 500) {
    const parca = taze.slice(i, i + 500);
    const eklenen = v<Satir[]>(await db.from("push_islenen")
      .upsert(parca.map((h) => ({ anahtar: `h:${h.id}` })), { onConflict: "anahtar", ignoreDuplicates: true })
      .select("anahtar"));
    const yeni = new Set(eklenen.map((x) => x.anahtar));
    hareketler.push(...parca.filter((h) => yeni.has(`h:${h.id}`)));
  }
  if (hareketler.length) {
    const cihaz = await sozluk(db, "cihazlar", "id, seri_no", hareketler.map((h) => h.cihaz_id));
    const urun = await sozluk(db, "urunler", "id, ad", hareketler.map((h) => h.urun_id));
    const depo = await sozluk(db, "depolar", "id, ad, tur", hareketler.flatMap((h) => [h.depo_id, h.hedef_depo_id]));
    const kisi = await sozluk(db, "kullanicilar", "id, ad", hareketler.map((h) => h.kullanici_id));
    hareketler = hareketler.map((h) => ({
      ...h,
      seri_no: cihaz.get(h.cihaz_id)?.seri_no ?? "-",
      urun_adi: urun.get(h.urun_id)?.ad ?? "-",
      depo_adi: depo.get(h.depo_id)?.ad ?? "-",
      hedef_adi: depo.get(h.hedef_depo_id)?.ad ?? "-",
      hedef_tur: depo.get(h.hedef_depo_id)?.tur,
      kullanici: kisi.get(h.kullanici_id)?.ad ?? "",
    }));
  }

  // 4) Yeni giriş kayıtları
  const girisSorgu = await db.from("giris_kayitlari").select("*")
    .gt("id", Number(ayar.imlec_giris)).order("id").limit(500);
  const girisler: Satir[] = girisSorgu.error ? [] : (girisSorgu.data ?? []);
  const girisImlec = girisler.reduce((m, g) => Math.max(m, Number(g.id)), Number(ayar.imlec_giris));

  if (aboneler.length === 0) {
    await ayarYaz(db, "imlec_hareket", String(yeniImlec));
    await ayarYaz(db, "imlec_giris", String(girisImlec));
    return { abone: 0, hareket: hareketler.length };
  }

  const acikMi = (a: Ayarlar, t: string) => (a.acik ?? VARSAYILAN_ACIK).includes(t);
  const herhangi = (t: string) => aboneler.some((x) => acikMi(x.ayarlar ?? {}, t));

  // 5) Ortak durum bilgileri (yalnızca gereken varsa sorgulanır)
  const kritik = herhangi("kritikStok") || herhangi("gunlukOzet") ? await kritikStoklar(db) : [];
  const servisler = herhangi("servisGecikmesi") || herhangi("gunlukOzet") ? await acikServisler(db) : [];
  const enUzunGaranti = Math.max(0, ...aboneler.map((x) => (x.ayarlar?.garantiGun ?? 30)));
  const garantiler = herhangi("garantiBitiyor") || herhangi("gunlukOzet")
    ? await garantisiBitecekler(db, enUzunGaranti, ms) : [];

  // Güvenlik: son 15 dakikadaki hatalı denemeler ve yeni IP'ler
  const hataliSayilari = new Map<string, Satir[]>();
  const yeniIpGirisleri: Satir[] = [];
  if (girisler.length && (herhangi("hataliSifre") || herhangi("yeniIpGiris"))) {
    if (girisler.some((g) => g.basarili === false)) {
      const son = v<Satir[]>(await db.from("giris_kayitlari").select("email, ip, tarih")
        .eq("basarili", false).gte("tarih", new Date(ms - 15 * 60 * 1000).toISOString()));
      for (const r of son) {
        const e = r.email ?? "-";
        hataliSayilari.set(e, [...(hataliSayilari.get(e) ?? []), r]);
      }
    }
    const bakilan = new Set<string>();
    for (const g of girisler.filter((g) => g.basarili !== false && g.email && g.ip)) {
      if (bakilan.has(`${g.email}|${g.ip}`)) continue;
      bakilan.add(`${g.email}|${g.ip}`);
      const once = v<Satir[]>(await db.from("giris_kayitlari").select("id")
        .eq("email", g.email).eq("ip", g.ip).eq("basarili", true).lt("id", g.id).limit(1));
      if (once.length === 0) yeniIpGirisleri.push(g);
    }
  }

  // 6) Her abone için bildirimler
  let gonderilen = 0, silinen = 0;
  for (const abone of aboneler) {
    const a: Ayarlar = abone.ayarlar ?? {};
    const gorulen = new Set(v<Satir[]>(await db.from("push_gorulen").select("anahtar")
      .eq("abonelik_id", abone.id)).map((x) => x.anahtar));
    const yeniGorulen: string[] = [];
    const silinecekGorulen: string[] = [];
    const isaretle = (k: string) => { gorulen.add(k); yeniGorulen.push(k); };
    const bildirimler: Bildirim[] = [];
    const ekle = (tur: string, baslik: string, govde: string) => bildirimler.push({ tur, baslik, govde });

    const benim = String(abone.kullanici_id);
    const baskasi = hareketler.filter((h) => String(h.kullanici_id) !== benim);
    const urunOzeti = (l: Satir[]) => {
      const say = new Map<string, number>();
      for (const h of l) say.set(h.urun_adi, (say.get(h.urun_adi) ?? 0) + 1);
      const p = [...say].map(([u, n]) => (n > 1 ? `${u} ×${n}` : u));
      return p.slice(0, 4).join(", ") + (p.length > 4 ? " ..." : "");
    };
    const kimler = (l: Satir[]) => {
      const k = [...new Set(l.map((h) => h.kullanici).filter(Boolean))];
      return k.length ? ` · ${k.slice(0, 2).join(", ")}` : "";
    };

    if (acikMi(a, "cihazGeldi")) {
      const izlenen = new Set(a.izlenenDepolar ?? []);
      const g = new Map<string, Satir[]>();
      for (const h of baskasi) {
        if (!h.hedef_depo_id || !["transfer", "kullanim", "iade"].includes(h.tip)) continue;
        if (izlenen.size && !izlenen.has(h.hedef_depo_id)) continue;
        g.set(h.hedef_depo_id, [...(g.get(h.hedef_depo_id) ?? []), h]);
      }
      for (const l of g.values()) {
        ekle("cihazGeldi", `${l[0].hedef_tur === "arac" ? "Araca" : "Depoya"} cihaz geldi: ${l[0].hedef_adi} (${l.length})`,
          urunOzeti(l) + kimler(l));
      }
    }
    if (acikMi(a, "depoyaGiris")) {
      const g = new Map<string, Satir[]>();
      for (const h of baskasi.filter((h) => h.tip === "girisi" && !h.sebep)) {
        g.set(h.depo_id, [...(g.get(h.depo_id) ?? []), h]);
      }
      for (const l of g.values()) {
        ekle("depoyaGiris", `Depoya giriş: ${l[0].depo_adi} (${l.length})`, urunOzeti(l) + kimler(l));
      }
    }
    if (acikMi(a, "hurdaSilme")) {
      const l = baskasi.filter((h) => h.tip === "hurda" || h.tip === "silme");
      if (l.length === 1) {
        const h = l[0];
        ekle("hurdaSilme", `${h.tip === "hurda" ? "Hurdaya ayrıldı" : "Silindi"}: ${h.seri_no}`,
          [h.urun_adi, h.sebep, h.kullanici].filter(Boolean).join(" · "));
      } else if (l.length > 1) {
        const hurda = l.filter((h) => h.tip === "hurda").length;
        ekle("hurdaSilme", `${l.length} cihaz: ${hurda} hurda, ${l.length - hurda} silme`,
          l.slice(0, 4).map((h) => `${h.seri_no} (${h.urun_adi})`).join(", "));
      }
    }
    if (acikMi(a, "yeniAriza")) {
      const l = baskasi.filter((h) => h.tip === "servis" && String(h.sebep ?? "").startsWith("Arıza kaydı"));
      if (l.length === 1) {
        ekle("yeniAriza", `Yeni arıza: ${l[0].seri_no}`,
          [l[0].urun_adi, String(l[0].sebep).replace("Arıza kaydı: ", ""), l[0].not_].filter(Boolean).join(" · "));
      } else if (l.length > 1) {
        ekle("yeniAriza", `${l.length} yeni arıza kaydı`, l.slice(0, 4).map((h) => `${h.seri_no} (${h.urun_adi})`).join(", "));
      }
    }
    if (acikMi(a, "servisDonus")) {
      for (const h of baskasi.filter((h) => h.tip === "servis" &&
        /^(Onarıldı|Değiştirildi|Servisten döndü)/.test(String(h.sebep ?? ""))).slice(0, 5)) {
        ekle("servisDonus", `Servisten döndü: ${h.seri_no}`, [h.urun_adi, h.sebep, h.not_].filter(Boolean).join(" · "));
      }
    }

    if (acikMi(a, "kritikStok")) {
      const simdiki = new Map(kritik.map((k) => [`kritik:${k.urunId}:${k.toplam === 0 ? "tukendi" : "kritik"}`, k]));
      for (const k of gorulen) {
        if (k.startsWith("kritik:") && !simdiki.has(k)) silinecekGorulen.push(k);
      }
      const yeni = [...simdiki].filter(([k]) => !gorulen.has(k)).map(([k, x]) => (isaretle(k), x));
      if (yeni.length === 1) {
        const k = yeni[0];
        ekle("kritikStok", k.toplam === 0 ? `Tükendi: ${k.urunAdi}` : `Kritik stok: ${k.urunAdi}`,
          `Depolar ${k.depoda} + araçlar ${k.aracta} = ${k.toplam} · minimum ${k.minStok}`);
      } else if (yeni.length > 1) {
        const biten = yeni.filter((k) => k.toplam === 0).length;
        ekle("kritikStok", `${yeni.length} ürün kritik stokta${biten ? ` (${biten} tükendi)` : ""}`,
          yeni.slice(0, 5).map((k) => `${k.urunAdi} (${k.toplam}/${k.minStok})`).join(", "));
      }
    }

    if (acikMi(a, "servisGecikmesi")) {
      const esik = (a.servisGecikmeGun ?? 15) * GUN;
      const l: string[] = [];
      for (const s of servisler) {
        const baz = Number(s.gonderim_tarihi ?? s.acilis_tarihi);
        if (ms - baz < esik) continue;
        const k = `${s.gonderim_tarihi ? "gecikme" : "bekleme"}:${s.id}`;
        if (gorulen.has(k)) continue;
        isaretle(k);
        const gun = Math.floor((ms - baz) / GUN);
        l.push(s.gonderim_tarihi
          ? `${s.seri_no}: ${gun} gündür serviste${s.firma ? ` (${s.firma})` : ""}`
          : `${s.seri_no}: ${gun} gündür arızalı bekliyor (servise gönderilmedi)`);
      }
      if (l.length) ekle("servisGecikmesi", l.length === 1 ? "Servis gecikmesi" : `${l.length} cihaz serviste gecikti`, l.slice(0, 4).join("\n"));
    }

    const garantiGun = a.garantiGun ?? 30;
    const benimGaranti = garantiler.filter((c) => Number(c.garanti_bitis) <= bugunBasi(simdi) + (garantiGun + 1) * GUN);
    if (acikMi(a, "garantiBitiyor")) {
      const l: string[] = [];
      for (const c of benimGaranti) {
        const k = `garanti:${c.id}:${c.garanti_bitis}`;
        if (gorulen.has(k)) continue;
        isaretle(k);
        l.push(`${c.seri_no} (${c.urun_adi}) · ${tarihMetni(Number(c.garanti_bitis))}`);
      }
      if (l.length) {
        ekle("garantiBitiyor", l.length === 1 ? "Garanti bitiyor" : `${l.length} cihazın garantisi ${garantiGun} gün içinde bitiyor`,
          l.slice(0, 4).join("\n") + (l.length > 4 ? "\n..." : ""));
      }
    }

    if (acikMi(a, "gunlukOzet")) {
      const y = yerel(simdi);
      const k = `ozet:${y.anahtar}`;
      const vakit = y.saat * 60 + y.dakika >= (a.ozetSaat ?? 8) * 60 + (a.ozetDakika ?? 30);
      if (vakit && !gorulen.has(k)) {
        isaretle(k);
        const bas = bugunBasi(simdi);
        const dun = await hareketSayilari(db, bas - GUN, bas);
        const t = (x: string) => dun.get(x) ?? 0;
        const serviste = servisler.filter((s) => s.gonderim_tarihi).length;
        const biten = kritik.filter((x) => x.toplam === 0).length;
        ekle("gunlukOzet", `Günlük özet · ${tarihMetni(ms)}`, [
          `Kritik stok: ${kritik.length} ürün${biten ? ` (${biten} tükendi)` : ""}`,
          `Arızalı bekleyen: ${servisler.length - serviste} · serviste: ${serviste}`,
          ...(benimGaranti.length ? [`Garantisi ${garantiGun} gün içinde bitecek: ${benimGaranti.length}`] : []),
          `Dün: giriş ${t("girisi")}, transfer/kullanıma verme ${t("transfer") + t("kullanim") + t("iade")}, hurda ${t("hurda")}`,
        ].join("\n"));
      }
    }

    if (acikMi(a, "hataliSifre")) {
      const saatAnahtari = yerel(simdi).anahtar + String(yerel(simdi).saat).padStart(2, "0");
      for (const [email, l] of hataliSayilari) {
        if (l.length < 3) continue;
        const k = `hatali:${email}:${saatAnahtari}`;
        if (gorulen.has(k)) continue;
        isaretle(k);
        const ipler = [...new Set(l.map((r) => r.ip).filter(Boolean))];
        ekle("hataliSifre", `Hatalı şifre denemesi: ${email}`, `${l.length} deneme · IP: ${ipler.slice(0, 3).join(", ")}`);
      }
    }
    if (acikMi(a, "yeniIpGiris")) {
      for (const g of yeniIpGirisleri) {
        if (String(g.kullanici_id) === benim) continue;
        const k = `ip:${g.email}:${g.ip}`;
        if (gorulen.has(k)) continue;
        isaretle(k);
        ekle("yeniIpGiris", `Yeni IP'den giriş: ${g.email}`, `${g.ip} · ${g.platform ?? ""} · ${saatMetni(new Date(g.tarih))}`);
      }
    }

    // Kaydet ve gönder
    if (silinecekGorulen.length) {
      v(await db.from("push_gorulen").delete().eq("abonelik_id", abone.id).in("anahtar", silinecekGorulen));
    }
    if (yeniGorulen.length) {
      v(await db.from("push_gorulen").upsert(
        yeniGorulen.map((anahtar) => ({ abonelik_id: abone.id, anahtar })),
        { onConflict: "abonelik_id,anahtar", ignoreDuplicates: true },
      ));
    }
    for (const b of bildirimler.slice(0, 6)) {
      try {
        const durum = await gonder(abone, { ...b, url: KONU }, vapid);
        if (durum === 404 || durum === 410) {
          v(await db.from("push_abonelikleri").delete().eq("id", abone.id));
          silinen++;
          break;
        }
        if (durum < 300) gonderilen++;
        else console.error("Gönderilemedi", abone.id, durum);
      } catch (e) {
        console.error("Gönderim hatası", abone.id, e);
      }
    }
  }

  await ayarYaz(db, "imlec_hareket", String(yeniImlec));
  await ayarYaz(db, "imlec_giris", String(girisImlec));
  // Eski işaretleri temizle
  await db.from("push_islenen").delete().lt("tarih", new Date(ms - 5 * GUN).toISOString());
  await db.from("push_gorulen").delete().like("anahtar", "ozet:%").lt("tarih", new Date(ms - 10 * GUN).toISOString());

  return { abone: aboneler.length, hareket: hareketler.length, gonderilen, silinen };
}

// ---------------------------------------------------------------------
// Durum sorguları (telefondaki yerel sorguların sunucu karşılığı)
// ---------------------------------------------------------------------

async function kritikStoklar(db: SupabaseClient) {
  const urunler = v<Satir[]>(await db.from("urunler").select("id, ad, min_stok_seviyesi")
    .eq("deleted", 0).gt("min_stok_seviyesi", 0));
  if (!urunler.length) return [];
  const depolar = new Map((await tum((b, e) => db.from("depolar").select("id, tur, deleted").range(b, e)))
    .map((d) => [d.id, d]));
  const say = new Map<string, { depoda: number; aracta: number }>();
  for (let i = 0; i < urunler.length; i += 80) {
    const idler = urunler.slice(i, i + 80).map((u) => u.id);
    const cihazlar = await tum((b, e) => db.from("cihazlar").select("urun_id, depo_id")
      .in("urun_id", idler).eq("durum", "depoda").eq("deleted", 0).is("servis_durumu", null).range(b, e));
    for (const c of cihazlar) {
      const d = depolar.get(c.depo_id);
      if (!d || d.deleted) continue;
      const s = say.get(c.urun_id) ?? { depoda: 0, aracta: 0 };
      if (d.tur === "arac") s.aracta++; else s.depoda++;
      say.set(c.urun_id, s);
    }
  }
  return urunler.map((u) => {
    const s = say.get(u.id) ?? { depoda: 0, aracta: 0 };
    return { urunId: u.id, urunAdi: u.ad, minStok: u.min_stok_seviyesi, depoda: s.depoda, aracta: s.aracta, toplam: s.depoda + s.aracta };
  }).filter((k) => k.toplam <= k.minStok);
}

async function acikServisler(db: SupabaseClient) {
  const l = v<Satir[]>(await db.from("servis_kayitlari")
    .select("id, cihaz_id, urun_id, acilis_tarihi, gonderim_tarihi, firma")
    .is("kapanis", null).eq("deleted", 0));
  const cihaz = await sozluk(db, "cihazlar", "id, seri_no", l.map((s) => s.cihaz_id));
  return l.map((s) => ({ ...s, seri_no: cihaz.get(s.cihaz_id)?.seri_no ?? "-" }));
}

async function garantisiBitecekler(db: SupabaseClient, gun: number, ms: number) {
  const bas = bugunBasi(new Date(ms));
  const l = await tum((b, e) => db.from("cihazlar").select("id, seri_no, urun_id, garanti_bitis")
    .eq("deleted", 0).neq("durum", "cikti")
    .gte("garanti_bitis", bas).lte("garanti_bitis", bas + (gun + 1) * GUN)
    .order("garanti_bitis").range(b, e));
  const urun = await sozluk(db, "urunler", "id, ad", l.map((c) => c.urun_id));
  return l.map((c) => ({ ...c, urun_adi: urun.get(c.urun_id)?.ad ?? "-" }));
}

async function hareketSayilari(db: SupabaseClient, bas: number, bit: number) {
  const l = await tum((b, e) => db.from("stok_hareketleri").select("tip")
    .eq("deleted", 0).not("cihaz_id", "is", null).gte("tarih", bas).lt("tarih", bit).range(b, e));
  const m = new Map<string, number>();
  for (const h of l) m.set(h.tip, (m.get(h.tip) ?? 0) + 1);
  return m;
}
