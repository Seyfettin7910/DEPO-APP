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
