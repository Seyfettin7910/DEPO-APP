-- Depo Takip 1.12.0: depoya geri almada sebep (Arıza, Değişim...)
-- Supabase > SQL Editor'da bir kez çalıştırın (uygulamayı güncellemeden ÖNCE).
alter table stok_hareketleri add column if not exists sebep text;
