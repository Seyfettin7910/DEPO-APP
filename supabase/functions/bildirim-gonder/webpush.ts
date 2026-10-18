// Web Push (RFC 8291 aes128gcm şifreleme + RFC 8292 VAPID) — yalnızca
// standart WebCrypto ile; dış kütüphane gerektirmez (Deno / Supabase Edge).

const enc = new TextEncoder();

export function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlCoz(s: string): Uint8Array {
  const t = s.replace(/-/g, "+").replace(/_/g, "/");
  const p = t + "=".repeat((4 - (t.length % 4)) % 4);
  const bin = atob(p);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function birlestir(...parcalar: Uint8Array[]): Uint8Array {
  const n = parcalar.reduce((t, p) => t + p.length, 0);
  const out = new Uint8Array(n);
  let o = 0;
  for (const p of parcalar) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

async function hmac(anahtar: Uint8Array, veri: Uint8Array): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey(
    "raw", anahtar, { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, veri));
}

/** Yeni VAPID anahtar çifti: genel anahtar (base64url, 65 bayt) + özel JWK. */
export async function vapidAnahtarUret(): Promise<{ genel: string; ozelJwk: string }> {
  const cift = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"],
  );
  const ham = new Uint8Array(await crypto.subtle.exportKey("raw", cift.publicKey));
  const jwk = await crypto.subtle.exportKey("jwk", cift.privateKey);
  return { genel: b64url(ham), ozelJwk: JSON.stringify(jwk) };
}

/** VAPID yetki başlığı (ES256 JWT). */
async function vapidBasligi(
  endpoint: string, genel: string, ozelJwk: string, konu: string,
): Promise<string> {
  const aud = new URL(endpoint).origin;
  const baslik = b64url(enc.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const govde = b64url(enc.encode(JSON.stringify({
    aud,
    exp: Math.floor(Date.now() / 1000) + 12 * 3600,
    sub: konu,
  })));
  const anahtar = await crypto.subtle.importKey(
    "jwk", JSON.parse(ozelJwk), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
  const imza = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, anahtar, enc.encode(`${baslik}.${govde}`),
  ));
  return `vapid t=${baslik}.${govde}.${b64url(imza)}, k=${genel}`;
}

/** İçeriği abonenin anahtarlarıyla şifreler (aes128gcm, tek kayıt). */
export async function sifrele(
  p256dh: string, auth: string, icerik: Uint8Array,
): Promise<Uint8Array> {
  const uaGenel = b64urlCoz(p256dh);
  const authSir = b64urlCoz(auth);

  const gecici = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"],
  );
  const asGenel = new Uint8Array(await crypto.subtle.exportKey("raw", gecici.publicKey));
  const uaAnahtar = await crypto.subtle.importKey(
    "raw", uaGenel, { name: "ECDH", namedCurve: "P-256" }, false, [],
  );
  const ecdh = new Uint8Array(await crypto.subtle.deriveBits(
    { name: "ECDH", public: uaAnahtar }, gecici.privateKey, 256,
  ));

  // RFC 8291 3.4
  const prkKey = await hmac(authSir, ecdh);
  const keyInfo = birlestir(enc.encode("WebPush: info\0"), uaGenel, asGenel);
  const ikm = await hmac(prkKey, birlestir(keyInfo, new Uint8Array([1])));

  const tuz = crypto.getRandomValues(new Uint8Array(16));
  const prk = await hmac(tuz, ikm);
  const cek = (await hmac(prk, birlestir(enc.encode("Content-Encoding: aes128gcm\0"), new Uint8Array([1])))).slice(0, 16);
  const nonce = (await hmac(prk, birlestir(enc.encode("Content-Encoding: nonce\0"), new Uint8Array([1])))).slice(0, 12);

  const aes = await crypto.subtle.importKey("raw", cek, { name: "AES-GCM" }, false, ["encrypt"]);
  const sifreli = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce }, aes, birlestir(icerik, new Uint8Array([2])),
  ));

  const rs = new Uint8Array([0, 0, 0x10, 0]); // 4096
  return birlestir(tuz, rs, new Uint8Array([asGenel.length]), asGenel, sifreli);
}

export interface Abonelik {
  endpoint: string;
  p256dh: string;
  auth: string;
}

/** Bildirimi gönderir; HTTP durum kodunu döndürür (404/410: abonelik ölü). */
export async function gonder(
  abone: Abonelik,
  veri: unknown,
  vapid: { genel: string; ozelJwk: string; konu: string },
  ttl = 24 * 3600,
): Promise<number> {
  const govde = await sifrele(abone.p256dh, abone.auth, enc.encode(JSON.stringify(veri)));
  const yanit = await fetch(abone.endpoint, {
    method: "POST",
    headers: {
      "Content-Encoding": "aes128gcm",
      "Content-Type": "application/octet-stream",
      "TTL": String(ttl),
      "Urgency": "normal",
      "Authorization": await vapidBasligi(abone.endpoint, vapid.genel, vapid.ozelJwk, vapid.konu),
    },
    body: govde,
  });
  try {
    await yanit.arrayBuffer();
  } catch (_) { /* gövde önemsiz */ }
  return yanit.status;
}
