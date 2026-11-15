// DEPO YÖNETİM SİSTEMİ 1.36.0 — kullanıcı hesap işlemleri (sunucu fonksiyonu).
//
// Gizli (service role) anahtar yalnız burada, Supabase sunucusunda durur;
// telefona hiç gelmez. Uygulama bu fonksiyonu çağırır:
//   sifre_talebi   (giriş yapmadan) "Şifremi unuttum": yöneticilere bildirim
//   gecici_giris   geçici şifreyle giriş yapıldı (kayıt + süre denetimi)
//   sifre_degistir kendi şifresini değiştirir (geçici şifreden sonra zorunlu)
//   ekle / sifirla / durum / guncelle   yalnız kullanıcı yönetimi yetkisiyle
// Her işlem hesap_islemleri tablosuna yazılır; şifre ya da kod asla yazılmaz.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const GECICI_SURE_MS = 15 * 60 * 1000;
const TALEP_ARALIK_MS = 15 * 60 * 1000;
const ROLLER = ["admin", "depoSorumlusu", "sahaKullanicisi", "gozlemci", "amir"];
const ROL_ADI: Record<string, string> = {
  admin: "Yönetici", depoSorumlusu: "Depo sorumlusu", sahaKullanicisi: "Saha",
  gozlemci: "Gözlemci", amir: "Amir",
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

class Hata extends Error {
  constructor(public kod: string, mesaj: string, public durum = 400) {
    super(mesaj);
  }
}

const yanit = (govde: unknown, durum = 200) =>
  new Response(JSON.stringify(govde), {
    status: durum,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

function v<T>(r: { data: T | null; error: any }): T {
  if (r.error) throw new Error(r.error.message ?? String(r.error));
  return r.data as T;
}

/** Rastgele 6 haneli kod (ör. "482915"). */
function geciciKod(): string {
  const b = new Uint32Array(1);
  crypto.getRandomValues(b);
  return String(b[0] % 1000000).padStart(6, "0");
}

function ipAdresi(req: Request): string | null {
  const x = req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-forwarded-for")?.split(",")[0] ??
    req.headers.get("x-real-ip");
  return x?.trim() || null;
}

/** Türkçe büyük harf (i → İ, ı → I). */
function trBuyuk(s: string): string {
  return s.replaceAll("i", "İ").replaceAll("ı", "I").toLocaleUpperCase("tr-TR");
}

type Satir = Record<string, any>;

async function kullanici(db: SupabaseClient, id: string): Promise<Satir | null> {
  const r = v<Satir[]>(await db.from("kullanicilar").select("*").eq("id", id).limit(1));
  return r[0] ?? null;
}

async function yetkisiVar(db: SupabaseClient, rol: string, yetki: string): Promise<boolean> {
  const r = v<Satir[]>(await db.from("yetkiler").select("izin")
    .eq("rol", rol).eq("yetki", yetki).eq("deleted", 0).limit(1));
  return r[0]?.izin === 1;
}

async function kaydet(db: SupabaseClient, k: Satir) {
  v(await db.from("hesap_islemleri").insert(k));
}

async function aktifYoneticiSayisi(db: SupabaseClient): Promise<number> {
  const r = v<Satir[]>(await db.from("kullanicilar").select("id")
    .eq("rol", "admin").eq("aktif", 1).eq("deleted", 0));
  return r.length;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  try {
    const govde = await req.json().catch(() => ({}));
    const islem = String(govde.islem ?? "");
    const ip = ipAdresi(req);

    // ------------------------------------------------------------
    // Giriş yapmadan: şifremi unuttum
    // ------------------------------------------------------------
    if (islem === "sifre_talebi") {
      const email = String(govde.email ?? "").trim().toLowerCase();
      // E-posta kayıtlı olsun olmasın aynı yanıt (hesap yoklanamaz).
      if (!email.includes("@") || email.length > 200) return yanit({ ok: true });
      const once = new Date(Date.now() - TALEP_ARALIK_MS).toISOString();
      const son = v<Satir[]>(await db.from("hesap_islemleri").select("id")
        .eq("tur", "sifre_talebi").eq("hedef_email", email).gte("tarih", once).limit(1));
      if (son.length > 0) return yanit({ ok: true });
      const k = v<Satir[]>(await db.from("kullanicilar").select("id, ad, aktif")
        .ilike("email", email).eq("deleted", 0).limit(1))[0];
      await kaydet(db, {
        tur: "sifre_talebi",
        hedef_id: k?.id ?? null,
        hedef_email: email,
        hedef_ad: k?.ad ?? null,
        aciklama: k ? (k.aktif === 1 ? null : "Pasif kullanıcı") : "Kayıtlı değil",
        ip,
      });
      return yanit({ ok: true });
    }

    // ------------------------------------------------------------
    // Giriş gerektirenler
    // ------------------------------------------------------------
    const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    const kullaniciYanit = await db.auth.getUser(jwt);
    const benAuth = kullaniciYanit.data?.user;
    if (!benAuth) throw new Hata("oturum", "Oturum geçersiz; yeniden giriş yapın", 401);
    const ben = await kullanici(db, benAuth.id);
    if (!ben || ben.deleted === 1) throw new Hata("kullanici_yok", "Kullanıcı kaydı bulunamadı", 403);
    if (ben.aktif !== 1) throw new Hata("pasif", "Hesabınız pasif", 403);
    const simdi = Date.now();

    if (islem === "gecici_giris" || islem === "sifre_degistir") {
      const bekliyor = ben.sifre_degistirmeli === 1;
      const doldu = bekliyor && (ben.gecici_bitis ?? 0) < simdi;
      if (doldu) {
        await kaydet(db, {
          tur: "gecici_suresi_doldu", yapan_id: ben.id, yapan_email: ben.email,
          hedef_id: ben.id, hedef_email: ben.email, hedef_ad: ben.ad, ip,
        });
        throw new Hata("sure_doldu",
          "Geçici şifrenin süresi doldu. Yöneticinizden yeni şifre isteyin.", 403);
      }
      if (islem === "gecici_giris") {
        if (bekliyor) {
          await kaydet(db, {
            tur: "gecici_giris", yapan_id: ben.id, yapan_email: ben.email,
            hedef_id: ben.id, hedef_email: ben.email, hedef_ad: ben.ad, ip,
          });
        }
        return yanit({ ok: true, bekliyor, bitis: ben.gecici_bitis });
      }
      const yeni = String(govde.yeni ?? "");
      if (yeni.length < 8 || !/[0-9]/.test(yeni) || !/[A-Za-zÇĞİÖŞÜçğıöşü]/.test(yeni)) {
        throw new Hata("zayif", "Şifre en az 8 karakter olmalı, harf ve rakam içermeli");
      }
      const r = await db.auth.admin.updateUserById(ben.id, { password: yeni });
      if (r.error) throw new Hata("auth", `Şifre değiştirilemedi: ${r.error.message}`);
      v(await db.from("kullanicilar").update({
        sifre_degistirmeli: 0, gecici_bitis: null, updated_at: simdi,
      }).eq("id", ben.id));
      await kaydet(db, {
        tur: "sifre_degisti", yapan_id: ben.id, yapan_email: ben.email,
        hedef_id: ben.id, hedef_email: ben.email, hedef_ad: ben.ad,
        aciklama: bekliyor ? "Geçici şifreden sonra" : null, ip,
      });
      return yanit({ ok: true });
    }

    // ------------------------------------------------------------
    // Yönetici işlemleri
    // ------------------------------------------------------------
    if (ben.sifre_degistirmeli === 1 || !(await yetkisiVar(db, ben.rol, "kullanici_yonetimi"))) {
      throw new Hata("yetki", "Bu işlem için kullanıcı yönetimi yetkisi gerekir", 403);
    }
    const yapan = { yapan_id: ben.id, yapan_email: ben.email, ip };

    if (islem === "ekle") {
      const email = String(govde.email ?? "").trim().toLowerCase();
      const ad = trBuyuk(String(govde.ad ?? "").trim());
      const rol = String(govde.rol ?? "");
      const unvan = String(govde.unvan ?? "").trim();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new Hata("email", "Geçerli bir e-posta yazın");
      if (!ad) throw new Hata("ad", "Ad soyad yazın");
      if (!ROLLER.includes(rol)) throw new Hata("rol", "Rol seçin");
      const varMi = v<Satir[]>(await db.from("kullanicilar").select("id").ilike("email", email).limit(1));
      if (varMi.length > 0) throw new Hata("zaten_var", "Bu e-postayla bir kullanıcı zaten var");
      const kod = geciciKod();
      const r = await db.auth.admin.createUser({ email, password: kod, email_confirm: true });
      if (r.error || !r.data.user) {
        const m = r.error?.message ?? "";
        if (/already|registered|exists/i.test(m)) {
          throw new Hata("zaten_var", "Bu e-posta Supabase'de zaten kayıtlı (uygulamaya hiç girmemiş olabilir)");
        }
        throw new Hata("auth", `Kullanıcı oluşturulamadı: ${m}`);
      }
      const id = r.data.user.id;
      v(await db.from("kullanicilar").upsert({
        id, ad, email, rol, unvan: unvan ? trBuyuk(unvan) : null, aktif: 1,
        sifre_degistirmeli: 1, gecici_bitis: simdi + GECICI_SURE_MS,
        updated_at: simdi, deleted: 0,
      }));
      await kaydet(db, {
        tur: "kullanici_ekleme", ...yapan, hedef_id: id, hedef_email: email, hedef_ad: ad,
        aciklama: `Rol: ${ROL_ADI[rol]}${unvan ? ` · ${trBuyuk(unvan)}` : ""}`,
      });
      return yanit({ ok: true, id, kod, bitis: simdi + GECICI_SURE_MS });
    }

    const hedefId = String(govde.id ?? "");
    const hedef = await kullanici(db, hedefId);
    if (!hedef) throw new Hata("yok", "Kullanıcı bulunamadı", 404);
    const hedefBilgi = { hedef_id: hedef.id, hedef_email: hedef.email, hedef_ad: hedef.ad };

    if (islem === "sifirla") {
      if (hedef.aktif !== 1) throw new Hata("pasif", "Pasif kullanıcının şifresi sıfırlanamaz; önce aktif yapın");
      const kod = geciciKod();
      const r = await db.auth.admin.updateUserById(hedef.id, { password: kod });
      if (r.error) throw new Hata("auth", `Şifre sıfırlanamadı: ${r.error.message}`);
      v(await db.from("kullanicilar").update({
        sifre_degistirmeli: 1, gecici_bitis: simdi + GECICI_SURE_MS, updated_at: simdi,
      }).eq("id", hedef.id));
      await kaydet(db, { tur: "sifre_sifirlama", ...yapan, ...hedefBilgi });
      return yanit({ ok: true, kod, bitis: simdi + GECICI_SURE_MS });
    }

    if (islem === "durum") {
      const aktif = govde.aktif === true;
      if (!aktif && hedef.id === ben.id) throw new Hata("kendin", "Kendinizi pasif yapamazsınız");
      if (!aktif && hedef.rol === "admin" && hedef.aktif === 1 && (await aktifYoneticiSayisi(db)) <= 1) {
        throw new Hata("son_yonetici", "Son aktif yönetici pasif yapılamaz");
      }
      const r = await db.auth.admin.updateUserById(hedef.id, {
        ban_duration: aktif ? "none" : "876000h",
      });
      if (r.error) throw new Hata("auth", `Hesap güncellenemedi: ${r.error.message}`);
      if (!aktif) {
        // Açık oturumları kapat (telefon en geç oturum yenilenince çıkar).
        await db.auth.admin.signOut(hedef.id, "global").catch(() => {});
      }
      v(await db.from("kullanicilar").update({ aktif: aktif ? 1 : 0, updated_at: simdi })
        .eq("id", hedef.id));
      await kaydet(db, { tur: aktif ? "aktif" : "pasif", ...yapan, ...hedefBilgi });
      return yanit({ ok: true });
    }

    if (islem === "guncelle") {
      const degisim: Satir = {};
      const notlar: string[] = [];
      if (govde.rol != null && govde.rol !== hedef.rol) {
        const rol = String(govde.rol);
        if (!ROLLER.includes(rol)) throw new Hata("rol", "Geçersiz rol");
        if (hedef.rol === "admin" && hedef.aktif === 1 && (await aktifYoneticiSayisi(db)) <= 1) {
          throw new Hata("son_yonetici", "Son aktif yöneticinin rolü değiştirilemez");
        }
        degisim.rol = rol;
        notlar.push(`${ROL_ADI[hedef.rol] ?? hedef.rol} → ${ROL_ADI[rol]}`);
      }
      if (govde.unvan !== undefined) {
        const unvan = String(govde.unvan ?? "").trim();
        const yeni = unvan ? trBuyuk(unvan) : null;
        if (yeni !== (hedef.unvan ?? null)) {
          degisim.unvan = yeni;
          notlar.push(`Unvan: ${yeni ?? "-"}`);
        }
      }
      if (govde.ad != null) {
        const ad = trBuyuk(String(govde.ad).trim());
        if (ad && ad !== hedef.ad) {
          degisim.ad = ad;
          await kaydet(db, {
            tur: "ad_degisti", ...yapan, ...hedefBilgi, aciklama: `${hedef.ad} → ${ad}`,
          });
        }
      }
      if (Object.keys(degisim).length === 0) return yanit({ ok: true });
      degisim.updated_at = simdi;
      v(await db.from("kullanicilar").update(degisim).eq("id", hedef.id));
      if (notlar.length > 0) {
        await kaydet(db, { tur: "rol_degisti", ...yapan, ...hedefBilgi, aciklama: notlar.join(" · ") });
      }
      return yanit({ ok: true });
    }

    throw new Hata("islem", "Bilinmeyen işlem");
  } catch (e) {
    if (e instanceof Hata) return yanit({ ok: false, kod: e.kod, mesaj: e.message }, e.durum);
    console.error(e);
    return yanit({ ok: false, kod: "sunucu", mesaj: String(e) }, 500);
  }
});
