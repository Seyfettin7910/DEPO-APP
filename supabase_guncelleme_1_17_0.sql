-- DEPO OTOMASYON SİSTEMİ 1.17.0: arıza / servis / hurda takibi
-- Supabase > SQL Editor'da bir kez çalıştırın (uygulamayı güncellemeden ÖNCE).
-- Tekrar çalıştırmak zararsızdır.
-- Not: 1.13.0 ve 1.14.0 sütunları da burada var (çalıştırılmadıysa eklenir).

alter table kullanim_kayitlari add column if not exists enlem double precision;
alter table kullanim_kayitlari add column if not exists boylam double precision;
alter table kullanim_kayitlari add column if not exists konum_hassasiyet double precision;
alter table kullanim_kayitlari add column if not exists il text;
alter table kullanim_kayitlari add column if not exists ilce text;
alter table kullanim_kayitlari add column if not exists mahalle text;

-- Cihazın arıza / servis / hurda durumu (sağlamsa boş)
alter table cihazlar add column if not exists servis_durumu text;

-- Arıza / servis dosyaları
create table if not exists servis_kayitlari (
  id text primary key, cihaz_id text not null, urun_id text not null,
  acilis_tarihi bigint not null, ariza_aciklama text, karar text not null,
  onarim_yeri text, firma text, gonderim_tarihi bigint, donus_tarihi bigint,
  sonuc text, sonuc_aciklama text, yeni_seri_no text, kapanis text,
  kapanis_tarihi bigint, kullanici_id text,
  updated_at bigint not null default 0,
  deleted integer not null default 0,
  synced_at bigint not null default 0);

create index if not exists servis_kayitlari_synced_idx on servis_kayitlari (synced_at);
drop trigger if exists senk_tetik on servis_kayitlari;
create trigger senk_tetik before insert or update on servis_kayitlari
  for each row execute function senk_tetik();
alter table servis_kayitlari enable row level security;
drop policy if exists giris_yapanlar on servis_kayitlari;
create policy giris_yapanlar on servis_kayitlari for all to authenticated
  using (true) with check (true);
