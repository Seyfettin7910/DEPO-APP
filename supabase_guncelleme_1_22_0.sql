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
