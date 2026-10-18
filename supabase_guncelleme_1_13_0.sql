-- Depo Takip 1.13.0: sahada kullanım anındaki GPS konumu
-- Supabase > SQL Editor'da bir kez çalıştırın (uygulamayı güncellemeden ÖNCE).
alter table kullanim_kayitlari add column if not exists enlem double precision;
alter table kullanim_kayitlari add column if not exists boylam double precision;
alter table kullanim_kayitlari add column if not exists konum_hassasiyet double precision;
