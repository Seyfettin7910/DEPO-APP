-- Depo Takip 1.14.0: kurulum noktasının il / ilçe / mahalle (köy) bilgisi
-- Supabase > SQL Editor'da bir kez çalıştırın (uygulamayı güncellemeden ÖNCE).
alter table kullanim_kayitlari add column if not exists il text;
alter table kullanim_kayitlari add column if not exists ilce text;
alter table kullanim_kayitlari add column if not exists mahalle text;
