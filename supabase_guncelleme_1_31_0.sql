-- DEPO YÖNETİM SİSTEMİ 1.31.0: okuma sayıları (telefon modeline göre)
-- Supabase > SQL Editor'da bir kez çalıştırın (Ctrl+A ile hepsini seçip Run).
-- Tekrar çalıştırmak zararsızdır.
--
-- * Her telefon günde bir satır gönderir (akşam 17:00-17:30; o saatte
--   gönderemezse ertesi gün). Kişisel veri yok: kullanıcıya bağlanmaz,
--   telefon başına rastgele bir kurulum kimliği tutulur.
-- * Anlık senkrona ve Realtime yayınına EKLENMEZ; telefonlara geri çekilmez.
--   Raporlar → "Okuma istatistikleri" buradan okur.
-- * Bu SQL çalıştırılana kadar sayılar telefonda bekler, silinmez.

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

select 'Tamam: okuma_istatistikleri hazır' as sonuc;
