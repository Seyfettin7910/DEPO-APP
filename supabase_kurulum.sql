-- Depo Takip: Supabase kurulum betiği
-- Supabase > SQL Editor > New query: tamamını yapıştırıp "Run" ile BİR KEZ çalıştırın.
-- Tekrar çalıştırmak zararsızdır.

-- 1) Tablolar
create table if not exists depolar (
  id text primary key, ad text not null, konum text, tur text not null default 'sabit');

-- 1.4.0: araçlar seyyar depo olarak depolar tablosunda tutulur (mevcut kurulumu günceller)
alter table depolar add column if not exists tur text not null default 'sabit';

create table if not exists urunler (
  id text primary key, ad text not null, barkod text, birim text default 'adet',
  kategori text, min_stok_seviyesi integer default 0, seri_takipli integer default 1);

create table if not exists araclar (
  id text primary key, plaka text not null, ad text, aciklama text);

create table if not exists kullanicilar (
  id text primary key, ad text not null, email text not null, rol text not null);

create table if not exists cihazlar (
  id text primary key, urun_id text not null, seri_no text not null unique,
  depo_id text, durum text not null, arac_id text, kullanim_yeri text,
  alim_tarihi bigint, firma text, ihale text, garanti_bitis bigint);
-- (eski kurulumlar için) alım / garanti sütunları
alter table cihazlar add column if not exists alim_tarihi bigint;
alter table cihazlar add column if not exists firma text;
alter table cihazlar add column if not exists ihale text;
alter table cihazlar add column if not exists garanti_bitis bigint;
alter table cihazlar add column if not exists servis_durumu text;

create table if not exists stok_hareketleri (
  id text primary key, urun_id text not null, depo_id text not null,
  hedef_depo_id text, tip text not null, miktar integer not null,
  kullanici_id text not null, tarih bigint not null, not_ text, cihaz_id text,
  sebep text);
alter table stok_hareketleri add column if not exists sebep text;

create table if not exists kullanim_kayitlari (
  id text primary key, stok_hareket_id text not null, arac_id text,
  kullanim_yeri text, not_ text, enlem double precision, boylam double precision,
  konum_hassasiyet double precision);
alter table kullanim_kayitlari add column if not exists enlem double precision;
alter table kullanim_kayitlari add column if not exists boylam double precision;
alter table kullanim_kayitlari add column if not exists konum_hassasiyet double precision;
alter table kullanim_kayitlari add column if not exists il text;
alter table kullanim_kayitlari add column if not exists ilce text;
alter table kullanim_kayitlari add column if not exists mahalle text;

-- 1.17.0: arıza / servis dosyaları
create table if not exists servis_kayitlari (
  id text primary key, cihaz_id text not null, urun_id text not null,
  acilis_tarihi bigint not null, ariza_aciklama text, karar text not null,
  onarim_yeri text, firma text, gonderim_tarihi bigint, donus_tarihi bigint,
  sonuc text, sonuc_aciklama text, yeni_seri_no text, kapanis text,
  kapanis_tarihi bigint, kullanici_id text);

-- 2) Senkron tetikleyicisi:
--    * Eski bir telefondan gelen eski veri, daha yeni veriyi ezemez.
--    * synced_at: sunucunun kendi saati (telefon saati yanlış olsa da değişiklikler kaçmaz).
create or replace function senk_tetik() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.synced_at := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  return new;
end $$;

-- 3) Ortak sütunlar, tetikleyici ve güvenlik (yalnızca giriş yapmış kullanıcılar)
do $$
declare t text;
begin
  foreach t in array array['depolar','urunler','araclar','kullanicilar',
                           'cihazlar','stok_hareketleri','kullanim_kayitlari',
                           'servis_kayitlari'] loop
    execute format('alter table %I add column if not exists updated_at bigint not null default 0', t);
    execute format('alter table %I add column if not exists deleted integer not null default 0', t);
    execute format('alter table %I add column if not exists synced_at bigint not null default 0', t);
    execute format('create index if not exists %I on %I (synced_at)', t || '_synced_idx', t);
    execute format('drop trigger if exists senk_tetik on %I', t);
    execute format('create trigger senk_tetik before insert or update on %I for each row execute function senk_tetik()', t);
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists giris_yapanlar on %I', t);
    execute format('create policy giris_yapanlar on %I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- ---------------------------------------------------------------
-- DEPO OTOMASYON SİSTEMİ 1.18.0: giriş kayıtları (kullanıcı + IP)
-- Supabase > SQL Editor'da bir kez çalıştırın. Tekrar çalıştırmak zararsızdır.
--
-- IP adresi telefondan değil, sunucunun gördüğü bağlantıdan alınır
-- (uygulama tarafından değiştirilemez). Kayıtlar uygulamadan okunabilir ama
-- kimse (yönetici dahil) uygulamadan değiştiremez veya silemez.

create table if not exists giris_kayitlari (
  id bigint generated always as identity primary key,
  tarih timestamptz not null default now(),
  kullanici_id uuid,
  email text,
  basarili boolean not null default true,
  ip text,
  platform text,
  surum text,
  tarayici text
);
create index if not exists giris_kayitlari_tarih_idx on giris_kayitlari (tarih desc);

alter table giris_kayitlari enable row level security;
revoke all on giris_kayitlari from anon, authenticated;
grant select on giris_kayitlari to authenticated;
drop policy if exists okuma on giris_kayitlari;
create policy okuma on giris_kayitlari for select to authenticated using (true);

-- İsteği yapanın IP adresi (Supabase'in ilettiği başlıklardan)
create or replace function istek_ip() returns text
language sql stable as $$
  select nullif(coalesce(
    current_setting('request.headers', true)::json->>'cf-connecting-ip',
    split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1),
    current_setting('request.headers', true)::json->>'x-real-ip'
  ), '')
$$;

-- Başarılı giriş: kullanıcı bilgisi oturumdan alınır
create or replace function giris_kaydet(p_platform text, p_surum text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  insert into giris_kayitlari (kullanici_id, email, basarili, ip, platform, surum, tarayici)
  values (auth.uid(), auth.jwt()->>'email', true, istek_ip(),
          left(p_platform, 60), left(p_surum, 20),
          left(current_setting('request.headers', true)::json->>'user-agent', 300));
end $$;

-- Hatalı şifre denemesi (giriş yapılmadan çağrılır; aynı IP'den
-- 10 dakikada en fazla 20 kayıt alınır)
create or replace function hatali_giris_kaydet(p_email text, p_platform text, p_surum text)
returns void language plpgsql security definer set search_path = public as $$
declare v_ip text := istek_ip();
begin
  if (select count(*) from giris_kayitlari
      where basarili = false and ip is not distinct from v_ip
        and tarih > now() - interval '10 minutes') >= 20 then
    return;
  end if;
  insert into giris_kayitlari (email, basarili, ip, platform, surum, tarayici)
  values (left(lower(trim(p_email)), 120), false, v_ip,
          left(p_platform, 60), left(p_surum, 20),
          left(current_setting('request.headers', true)::json->>'user-agent', 300));
end $$;

revoke all on function giris_kaydet(text, text) from public;
revoke all on function hatali_giris_kaydet(text, text, text) from public;
grant execute on function giris_kaydet(text, text) to authenticated;
grant execute on function hatali_giris_kaydet(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------
-- DEPO OTOMASYON SİSTEMİ 1.22.0: kurum etiketi (barkod / karekod)
-- Supabase > SQL Editor'da bir kez çalıştırın. Tekrar çalıştırmak zararsızdır.
--
-- * kurum_kodlari  : ayarlardan tanımlanan kurum kodları (BLD, BLD-BIM ...)
-- * kurum_ayarlari : herkeste aynı olan ayarlar (etiket doğrulaması / engeli)
-- * etiketler      : cihazların kurum etiketi kodları ve durumları
-- * etiket_hareketleri : etiket geçmişi (üretildi, basıldı, doğrulandı...)
--   Bu kayıtlar kimse tarafından (yönetici dahil) değiştirilemez, silinemez.

create table if not exists kurum_kodlari (
  id text primary key, kod text not null, ad text,
  aktif integer not null default 1, sira integer not null default 0);

create table if not exists kurum_ayarlari (
  id text primary key, deger text);

create table if not exists etiketler (
  id text primary key, cihaz_id text not null, kod text not null,
  kurum_kodu_id text, surum integer not null default 1, durum text not null,
  seri_nosuz integer not null default 0, olusturma bigint not null,
  kullanici_id text);
create unique index if not exists etiketler_kod_uq on etiketler (kod);
create index if not exists etiketler_cihaz_idx on etiketler (cihaz_id);

create table if not exists etiket_hareketleri (
  id text primary key, etiket_id text not null, cihaz_id text not null,
  islem text not null, surum integer, aciklama text, kullanici_id text,
  tarih bigint not null);
create index if not exists etiket_hareketleri_etiket_idx on etiket_hareketleri (etiket_id);
create index if not exists etiket_hareketleri_cihaz_idx on etiket_hareketleri (cihaz_id);

-- Ortak senkron sütunları, tetikleyici ve güvenlik (yalnızca giriş yapmış kullanıcılar)
do $$
declare t text;
begin
  foreach t in array array['kurum_kodlari','kurum_ayarlari','etiketler','etiket_hareketleri'] loop
    execute format('alter table %I add column if not exists updated_at bigint not null default 0', t);
    execute format('alter table %I add column if not exists deleted integer not null default 0', t);
    execute format('alter table %I add column if not exists synced_at bigint not null default 0', t);
    execute format('create index if not exists %I on %I (synced_at)', t || '_synced_idx', t);
    execute format('drop trigger if exists senk_tetik on %I', t);
    execute format('create trigger senk_tetik before insert or update on %I for each row execute function senk_tetik()', t);
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists giris_yapanlar on %I', t);
    execute format('create policy giris_yapanlar on %I for all to authenticated using (true) with check (true)', t);
  end loop;
end $$;

-- Etiket geçmişi değiştirilemez ve silinemez. (Aynı kaydın telefondan
-- tekrar gönderilmesi hata vermez; kayıt olduğu gibi kalır.)
create or replace function etiket_hareket_koru() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    return null;
  end if;
  return old;
end $$;
drop trigger if exists a_koru on etiket_hareketleri;
create trigger a_koru before update or delete on etiket_hareketleri
  for each row execute function etiket_hareket_koru();

-- ---------------------------------------------------------------
-- DEPO OTOMASYON SİSTEMİ 1.24.0: montaj tutanağı
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır.
--
-- * kullanim_kayitlari.tutanak : alindi | alinacak | kurum_ici (eski kayıtlarda boş)
-- * Miktarlı malzemeler (kablo, adaptör…) mevcut tablolarla çalışır:
--   urunler.seri_takipli = 0 olan ürünlerin hareketleri stok_hareketleri'ne
--   cihaz_id boş, miktar dolu olarak yazılır. Yeni tablo gerekmez.

alter table kullanim_kayitlari add column if not exists tutanak text;
alter table kullanim_kayitlari add column if not exists tutanak_tarihi bigint;
alter table kullanim_kayitlari add column if not exists tutanak_kullanici_id text;

-- Sunucunun sütun listesini hemen yenile
notify pgrst, 'reload schema';

-- DEPO OTOMASYON SİSTEMİ 1.27.0: malzemede kutu / top içeriği
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır.
--
-- * urunler.kutu_icerigi : miktarlı malzemede bir kutu / topun içeriği
--   (ör. 305 metre). Barkodu her okutuşta bu kadar eklenir. Boşsa 1.
-- * Bu SQL çalıştırılana kadar uygulama çalışır; yalnız kutu içeriği
--   diğer telefonlara gitmez.

alter table urunler add column if not exists kutu_icerigi integer;

-- Sunucunun sütun listesini hemen yenile
notify pgrst, 'reload schema';

-- DEPO OTOMASYON SİSTEMİ 1.29.0: anlık senkron (Realtime "zili")
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır.
--
-- * Tablolar Supabase'in "supabase_realtime" yayınına eklenir: bir telefonda
--   kayıt yapılınca sunucu diğer telefonlara "şu tabloda değişiklik var" der,
--   onlar yalnız o tabloyu kaldığı yerden çeker.
-- * Herkes yalnızca görme yetkisi olan kayıtların haberini alır (RLS).
-- * Bu SQL çalıştırılana kadar uygulama çalışır; telefonlar değişiklikleri
--   5 dakikada bir (ve uygulama açılınca / internet gelince) alır.

do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array[
    'depolar', 'urunler', 'araclar', 'kullanicilar', 'kurum_kodlari',
    'kurum_ayarlari', 'cihazlar', 'stok_hareketleri', 'kullanim_kayitlari',
    'servis_kayitlari', 'etiketler', 'etiket_hareketleri'
  ] loop
    if exists (select 1 from information_schema.tables
               where table_schema = 'public' and table_name = t)
       and not exists (select 1 from pg_publication_tables
                       where pubname = 'supabase_realtime'
                         and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Kontrol: aşağıdaki sorgu 12 tabloyu listelemeli.
select tablename from pg_publication_tables
where pubname = 'supabase_realtime' and schemaname = 'public'
order by tablename;

-- DEPO OTOMASYON SİSTEMİ 1.30.0: ürün birleştirme
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır.
--
-- * urunler.birlesti_id : bu ürün başka bir ürüne katıldıysa kalan ürünün id'si.
--   İnternetsizken eski ürünle kaydedilmiş cihaz / hareket sonradan gelirse
--   telefonlar bu bilgiyle kaydı kalan ürüne aktarır.
-- * Bu SQL çalıştırılana kadar birleştirme yine çalışır (cihazlar ve
--   hareketler taşınır); yalnız diğer telefonlar "hangi ürüne birleşti"
--   bilgisini alamaz.

alter table urunler add column if not exists birlesti_id text;

-- Sunucunun sütun listesini hemen yenile
notify pgrst, 'reload schema';

-- DEPO YÖNETİM SİSTEMİ 1.31.0: okuma sayıları (telefon modeline göre)
create table if not exists okuma_istatistikleri (
  id text primary key,                 -- kurulum_id + '_' + gün
  kurulum_id text not null,
  gun date not null,
  platform text,                       -- "Uygulama · Android", "Web · Windows · Edge"
  marka text,
  model text,
  isletim_sistemi text,
  uygulama_surumu text,
  barkod integer not null default 0,
  karekod integer not null default 0,
  yazi integer not null default 0,
  evet integer not null default 0,     -- yazıdan okunan "Doğru mu?" → Evet
  hayir integer not null default 0,
  kamera_durdu integer not null default 0,
  sure_toplam_ms bigint not null default 0,
  sure_adet integer not null default 0,
  yok_sayilan jsonb not null default '{}'::jsonb,  -- sebep → adet
  yakinlik jsonb not null default '{}'::jsonb,     -- "2x" → adet
  guncellendi timestamptz not null default now()
);
create index if not exists okuma_istatistikleri_gun_idx
  on okuma_istatistikleri (gun desc);

alter table okuma_istatistikleri enable row level security;
revoke all on okuma_istatistikleri from anon;
grant select, insert, update on okuma_istatistikleri to authenticated;

drop policy if exists okuma on okuma_istatistikleri;
create policy okuma on okuma_istatistikleri
  for select to authenticated using (true);
drop policy if exists ekleme on okuma_istatistikleri;
create policy ekleme on okuma_istatistikleri
  for insert to authenticated with check (true);
drop policy if exists guncelleme on okuma_istatistikleri;
create policy guncelleme on okuma_istatistikleri
  for update to authenticated using (true) with check (true);

-- Sunucunun tablo listesini hemen yenile
notify pgrst, 'reload schema';

