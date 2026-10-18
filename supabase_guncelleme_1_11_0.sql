-- Depo Takip 1.11.0: cihazlara alım / garanti bilgileri
-- Supabase > SQL Editor'da bir kez çalıştırın (uygulamayı 1.11.0'a
-- güncellemeden ÖNCE). Tekrar çalıştırmak zararsızdır.
alter table cihazlar add column if not exists alim_tarihi bigint;
alter table cihazlar add column if not exists firma text;
alter table cihazlar add column if not exists ihale text;
alter table cihazlar add column if not exists garanti_bitis bigint;
